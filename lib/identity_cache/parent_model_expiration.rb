# frozen_string_literal: true
module IdentityCache
  # @api private
  module ParentModelExpiration
    extend ActiveSupport::Concern
    include ArTransactionChanges

    class << self
      def add_parent_expiry_hook(cached_association)
        name = cached_association.reflection.class_name.demodulize
        lazy_hooks[name] << ExpiryHook.new(cached_association)
      end

      def install_all_pending_parent_expiry_hooks
        until lazy_hooks.empty?
          lazy_hooks.keys.each do |name|
            if (hooks = lazy_hooks.delete(name))
              hooks.each(&:install)
            end
          end
        end
      end

      def install_pending_parent_expiry_hooks(model)
        return if lazy_hooks.empty?
        name = model.name.demodulize
        if (hooks = lazy_hooks.delete(name))
          hooks.each(&:install)
        end
      end

      private

      def lazy_hooks
        @lazy_hooks ||= Hash.new { |hash, key| hash[key] = [] }
      end
    end

    module ClassMethods
      def parent_expiration_entries
        ParentModelExpiration.install_pending_parent_expiry_hooks(cached_model)
        _parent_expiration_entries
      end
    end

    included do
      class_attribute(:_parent_expiration_entries)
      self._parent_expiration_entries = Hash.new { |hash, key| hash[key] = [] }
    end

    def expire_parent_caches
      parents_to_expire = Set.new
      add_parents_to_cache_expiry_set(parents_to_expire)
      parents_to_expire.each do |parent|
        parent.expire_primary_index if parent.class.primary_cache_index_enabled
      end
    end

    def add_parents_to_cache_expiry_set(parents_to_expire)
      self.class.parent_expiration_entries.each do |association_name, cached_associations|
        parents_to_expire_on_changes(parents_to_expire, association_name, cached_associations)
      end
    end

    def add_record_to_cache_expiry_set(parents_to_expire, record)
      if parents_to_expire.add?(record)
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
        if new_parent&.is_a?(parent_class) &&
           should_expire_identity_cache_parent?(foreign_key, only_on_foreign_key_change)
          add_record_to_cache_expiry_set(parents_to_expire, new_parent)
        end

        if old_parent&.is_a?(parent_class)
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
