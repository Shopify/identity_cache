module IdentityCache
  module ParentModelExpiration # :nodoc:
    extend ActiveSupport::Concern

    class << self
      def add_parent_expiry_hook(cached_association_hash)
        association_reflection = cached_association_hash[:association_reflection]
        name = model_basename(association_reflection.class_name)
        lazy_hooks[name] ||= []
        lazy_hooks[name] << cached_association_hash
      end

      def install_all_pending_parent_expiry_hooks
        until lazy_hooks.empty?
          lazy_hooks.keys.each do |key|
            lazy_hooks.delete(key).each do |cached_association_hash|
              install_hook(cached_association_hash)
            end
          end
        end
      end

      def install_pending_parent_expiry_hooks(model)
        name = model_basename(model.name)
        lazy_hooks.delete(name).try!(:each) do |cached_association_hash|
          install_hook(cached_association_hash)
        end
      end

      def check_association(cached_association_hash)
        association_reflection = cached_association_hash[:association_reflection]
        parent_model = association_reflection.active_record
        child_model = association_reflection.klass

        unless child_model < IdentityCache
          message = "cached association #{parent_model}\##{association_reflection.name} requires" \
            " associated class #{child_model} to include IdentityCache"
          message << " or IdentityCache::WithoutPrimaryIndex" if cached_association_hash[:embed] == true
          raise UnsupportedAssociationError, message
        end

        cached_association_hash[:inverse_name] ||= association_reflection.inverse_of.try!(:name) || parent_model.name.underscore.to_sym
        unless child_model.reflect_on_association(cached_association_hash[:inverse_name])
          raise InverseAssociationError, "Inverse name for association #{parent_model}\##{association_reflection.name} could not be determined. " \
            "Please use the :inverse_name option to specify the inverse association name for this cache."
        end
      end

      private

      def model_basename(name)
        name.split("::").last
      end

      def lazy_hooks
        @lazy_hooks ||= {}
      end

      def install_hook(cached_association_hash)
        check_association(cached_association_hash)

        association_reflection = cached_association_hash[:association_reflection]
        parent_model = association_reflection.active_record
        child_model = association_reflection.klass

        parent_expiration_entry = [parent_model, cached_association_hash[:only_on_foreign_key_change]]
        child_model.parent_expiration_entries[cached_association_hash[:inverse_name]] << parent_expiration_entry
      end
    end

    included do |base|
      base.class_attribute :parent_expiration_entries
      base.parent_expiration_entries = Hash.new{ |hash, key| hash[key] = [] }

      base.after_commit :expire_parent_caches
    end

    def expire_parent_caches
      ParentModelExpiration.install_pending_parent_expiry_hooks(cached_model)
      parents_to_expire = {}
      add_parents_to_cache_expiry_set(parents_to_expire)
      parents_to_expire.each_value do |parent|
        parent.send(:expire_primary_index)
      end
    end

    def add_parents_to_cache_expiry_set(parents_to_expire)
      self.class.parent_expiration_entries.each do |association_name, cached_associations|
        parents_to_expire_on_changes(parents_to_expire, association_name, cached_associations)
      end
    end

    def add_record_to_cache_expiry_set(parents_to_expire, record)
      key = record.primary_cache_index_key
      unless parents_to_expire[key]
        parents_to_expire[key] = record
        record.add_parents_to_cache_expiry_set(parents_to_expire)
      end
    end

    def parents_to_expire_on_changes(parents_to_expire, association_name, cached_associations)
      parent_association = self.class.reflect_on_association(association_name)
      foreign_key = parent_association.association_foreign_key

      new_parent = send(association_name)

      old_parent = nil
      if transaction_changed_attributes[foreign_key].present?
        begin
          if parent_association.polymorphic?
            parent_class_name = transaction_changed_attributes[parent_association.foreign_type]
            parent_class_name ||= read_attribute(parent_association.foreign_type)
            klass = parent_class_name.try!(:safe_constantize)
          else
            klass = parent_association.klass
          end
          old_parent = klass.find(transaction_changed_attributes[foreign_key])
        rescue ActiveRecord::RecordNotFound
          # suppress errors finding the old parent if its been destroyed since it will have expired itself in that case
        end
      end

      cached_associations.each do |parent_class, only_on_foreign_key_change|
        if new_parent && new_parent.is_a?(parent_class) && should_expire_identity_cache_parent?(foreign_key, only_on_foreign_key_change)
          add_record_to_cache_expiry_set(parents_to_expire, new_parent)
        end

        if old_parent && old_parent.is_a?(parent_class)
          add_record_to_cache_expiry_set(parents_to_expire, old_parent)
        end
      end
    end

    def should_expire_identity_cache_parent?(foreign_key, only_on_foreign_key_change)
      if only_on_foreign_key_change
        destroyed? || was_new_record? || transaction_changed_attributes[foreign_key].present?
      else
        true
      end
    end
  end
  private_constant :ParentModelExpiration
end
