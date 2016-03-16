module IdentityCache
  module ParentModelExpiration # :nodoc:
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute :parent_expiration_entries
      base.parent_expiration_entries = Hash.new{ |hash, key| hash[key] = [] }
    end

    def expire_parent_caches
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
        record.add_parents_to_cache_expiry_set(parents_to_expire) if record.respond_to?(:add_parents_to_cache_expiry_set, true)
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
end
