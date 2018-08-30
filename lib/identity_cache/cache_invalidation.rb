module IdentityCache
  module CacheInvalidation

    CACHE_KEY_NAMES = [:ids_variable_name, :records_variable_name]

    def reload(*)
      clear_cached_associations
      super
    end

    private

    def clear_cached_associations
      self.class.send(:all_cached_associations).each do |_, data|
        CACHE_KEY_NAMES.each do |key|
          if data[key]
            instance_variable_name = data[key]
            if instance_variable_defined?(instance_variable_name)
              remove_instance_variable(instance_variable_name)
            end
          end
        end
      end
    end
  end
end
