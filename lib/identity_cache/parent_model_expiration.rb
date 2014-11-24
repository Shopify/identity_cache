module IdentityCache
  module ParentModelExpiration # :nodoc:
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute :parent_expiration_entries
      base.parent_expiration_entries = Set.new
    end
  
    module ClassMethods
      private

      def add_parent_expiration_entry(after_action_name)
        parent_expiration_entries << after_action_name
      end
    end
    
    def expire_parent_caches
      self.class.parent_expiration_entries.each do |parent_expiration_entry|
        send(parent_expiration_entry)
      end
    end

    def expire_parent_cache_on_changes(parent_name, foreign_key, parent_class, only_on_foreign_key_change)
      new_parent = send(parent_name)

      if new_parent && new_parent.respond_to?(:expire_primary_index, true)
        if should_expire_identity_cache_parent?(foreign_key, only_on_foreign_key_change)
          new_parent.send(:expire_primary_index)
          new_parent.send(:expire_parent_caches) if new_parent.respond_to?(:expire_parent_caches, true)
        end
      end

      if transaction_changed_attributes[foreign_key].present?
        begin
          old_parent = parent_class.find(transaction_changed_attributes[foreign_key])
          old_parent.send(:expire_primary_index) if old_parent.respond_to?(:expire_primary_index, true)
          old_parent.send(:expire_parent_caches)  if old_parent.respond_to?(:expire_parent_caches, true)
        rescue ActiveRecord::RecordNotFound => e
          # suppress errors finding the old parent if its been destroyed since it will have expired itself in that case
        end
      end

      true
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
