module IdentityCache
  module ParentModelExpiration # :nodoc:
    def expire_parent_cache_on_changes(parent_name, foreign_key, parent_class, only_on_foreign_key_change)
      new_parent = send(parent_name)

      if new_parent && new_parent.respond_to?(:expire_primary_index, true)
        if should_expire_identity_cache_parent?(foreign_key, only_on_foreign_key_change)
          new_parent.send(:expire_primary_index)
          new_parent.send(:expire_parent_cache) if new_parent.respond_to?(:expire_parent_cache, true)
        end
      end

      if transaction_changed_attributes[foreign_key].present?
        begin
          old_parent = parent_class.find(transaction_changed_attributes[foreign_key])
          old_parent.send(:expire_primary_index) if old_parent.respond_to?(:expire_primary_index, true)
          old_parent.send(:expire_parent_cache)  if old_parent.respond_to?(:expire_parent_cache, true)
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
