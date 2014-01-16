module IdentityCache
  module ConfigurationDSL
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute :cache_indexes
      base.class_attribute :cache_attributes
      base.class_attribute :cached_has_manys
      base.class_attribute :cached_has_ones
      base.class_attribute :primary_cache_index_enabled

      base.cached_has_manys = {}
      base.cached_has_ones = {}
      base.cache_attributes = []
      base.cache_indexes = []
      base.primary_cache_index_enabled = true

      base.private_class_method :build_normalized_has_many_cache, :build_denormalized_association_cache,
                                :add_parent_expiry_hook, :identity_cache_multiple_value_dynamic_fetcher,
                                :identity_cache_single_value_dynamic_fetcher, :identity_cache_sql_conditions
    end

    module ClassMethods
      # Declares a new index in the cache for the class where IdentityCache was
      # included.
      #
      # IdentityCache will add a fetch_by_field1_and_field2_and_...field for every
      # index.
      #
      # == Example:
      #
      #  class Product
      #    include IdentityCache
      #    cache_index :name, :vendor
      #  end
      #
      # Will add Product.fetch_by_name_and_vendor
      #
      # == Parameters
      #
      # +fields+ Array of symbols or strings representing the fields in the index
      #
      # == Options
      # * unique: if the index would only have unique values
      #
      def cache_index(*fields)
        raise NotImplementedError, "Cache indexes need an enabled primary index" unless primary_cache_index_enabled
        options = fields.extract_options!
        self.cache_indexes.push fields

        field_list = fields.join("_and_")
        arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')

        if options[:unique]
          self.instance_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
            def fetch_by_#{field_list}(#{arg_list})
              identity_cache_single_value_dynamic_fetcher(#{fields.inspect}, [#{arg_list}])
            end

            # exception throwing variant
            def fetch_by_#{field_list}!(#{arg_list})
              fetch_by_#{field_list}(#{arg_list}) or raise ActiveRecord::RecordNotFound
            end
          CODE
        else
          self.instance_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
            def fetch_by_#{field_list}(#{arg_list})
              identity_cache_multiple_value_dynamic_fetcher(#{fields.inspect}, [#{arg_list}])
            end
          CODE
        end
      end


      # Will cache an association to the class including IdentityCache.
      # The embed option, if set, will make IdentityCache keep the association
      # values in the same cache entry as the parent.
      #
      # Embedded associations are more effective in offloading database work,
      # however they will increase the size of the cache entries and make the
      # whole entry expire when any of the embedded members change.
      #
      # == Example:
      #   class Product
      #    cached_has_many :options, :embed => false
      #    cached_has_many :orders
      #    cached_has_many :buyers, :inverse_name => 'line_item'
      #   end
      #
      # == Parameters
      # +association+ Name of the association being cached as a symbol
      #
      # == Options
      #
      # * embed: If set will cause IdentityCache to keep the values for this
      #   association in the same cache entry as the parent, instead of its own.
      # * inverse_name: The name of the parent in the association if the name is
      #   not the lowercase pluralization of the parent object's class
      def cache_has_many(association, options = {})
        options[:embed] ||= false
        options[:inverse_name] ||= self.name.underscore.to_sym
        raise InverseAssociationError unless self.reflect_on_association(association)
        self.cached_has_manys[association] = options

        if options[:embed]
          build_denormalized_association_cache(association, options)
        else
          build_normalized_has_many_cache(association, options)
        end
      end

      # Will cache an association to the class including IdentityCache.
      # The embed option if set will make IdentityCache keep the association
      # values in the same cache entry as the parent.
      #
      # Embedded associations are more effective in offloading database work,
      # however they will increase the size of the cache entries and make the
      # whole entry expire with the change of any of the embedded members
      #
      # == Example:
      #   class Product
      #    cached_has_one :store, :embed => false
      #    cached_has_one :vendor
      #   end
      #
      # == Parameters
      # +association+ Symbol with the name of the association being cached
      #
      # == Options
      #
      # * embed: If set will cause IdentityCache to keep the values for this
      #   association in the same cache entry as the parent, instead of its own.
      # * inverse_name: The name of the parent in the association ( only
      #   necessary if the name is not the lowercase pluralization of the
      #   parent object's class)
      def cache_has_one(association, options = {})
        options[:embed] ||= true
        options[:inverse_name] ||= self.name.underscore.to_sym
        raise InverseAssociationError unless self.reflect_on_association(association)
        self.cached_has_ones[association] = options

        if options[:embed]
          build_denormalized_association_cache(association, options)
        else
          raise NotImplementedError
        end
      end

      # Will cache a single attribute on its own blob, it will add a
      # fetch_attribute_by_id (or the value of the by option).
      #
      # == Example:
      #   class Product
      #    cache_attribute :quantity, :by => :name
      #    cache_attribute :quantity  :by => [:name, :vendor]
      #   end
      #
      # == Parameters
      # +attribute+ Symbol with the name of the attribute being cached
      #
      # == Options
      #
      # * by: Other attribute or attributes in the model to keep values indexed. Default is :id
      def cache_attribute(attribute, options = {})
        options[:by] ||= :id
        fields = Array(options[:by])

        self.cache_attributes.push [attribute, fields]

        field_list = fields.join("_and_")
        arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')

        self.instance_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
          def fetch_#{attribute}_by_#{field_list}(#{arg_list})
            attribute_dynamic_fetcher(#{attribute.inspect}, #{fields.inspect}, [#{arg_list}])
          end
        CODE
      end

      def disable_primary_cache_index
        raise NotImplementedError, "Secondary indexes rely on the primary index to function. You must either remove the secondary indexes or don't disable the primary" if self.cache_indexes.size > 0
        self.primary_cache_index_enabled = false
      end

      def identity_cache_single_value_dynamic_fetcher(fields, values) # :nodoc:
        sql_on_miss = "SELECT #{quoted_primary_key} FROM #{quoted_table_name} WHERE #{identity_cache_sql_conditions(fields, values)} LIMIT 1"
        cache_key = rails_cache_index_key_for_fields_and_values(fields, values)
        id = IdentityCache.fetch(cache_key) { connection.select_value(sql_on_miss) }
        unless id.nil?
          record = fetch_by_id(id.to_i)
          IdentityCache.cache.delete(cache_key) unless record
        end

        record
      end

      def identity_cache_multiple_value_dynamic_fetcher(fields, values) # :nodoc
        sql_on_miss = "SELECT #{quoted_primary_key} FROM #{quoted_table_name} WHERE #{identity_cache_sql_conditions(fields, values)}"
        cache_key = rails_cache_index_key_for_fields_and_values(fields, values)
        ids = IdentityCache.fetch(cache_key) { connection.select_values(sql_on_miss) }

        ids.empty? ? [] : fetch_multi(*ids)
      end

      def build_denormalized_association_cache(association, options) #:nodoc:
        options[:association_class]      ||= reflect_on_association(association).klass
        options[:cached_accessor_name]   ||= "fetch_#{association}"
        options[:records_variable_name]     ||= "cached_#{association}"
        options[:population_method_name] ||= "populate_#{association}_cache"


        unless instance_methods.include?(options[:cached_accessor_name].to_sym)
          self.class_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
            def #{options[:cached_accessor_name]}
              fetch_denormalized_cached_association('#{options[:records_variable_name]}', :#{association})
            end

            def #{options[:population_method_name]}
              populate_denormalized_cached_association('#{options[:records_variable_name]}', :#{association})
            end
          CODE

          add_parent_expiry_hook(options.merge(:only_on_foreign_key_change => false))
        end
      end

      def build_normalized_has_many_cache(association, options) #:nodoc:
        singular_association = association.to_s.singularize
        options[:association_class]       ||= reflect_on_association(association).klass
        options[:cached_accessor_name]    ||= "fetch_#{association}"
        options[:ids_name]                ||= "#{singular_association}_ids"
        options[:cached_ids_name]         ||= "fetch_#{options[:ids_name]}"
        options[:ids_variable_name]       ||= "cached_#{options[:ids_name]}"
        options[:records_variable_name]   ||= "cached_#{association}"
        options[:population_method_name]  ||= "populate_#{association}_cache"
        options[:prepopulate_method_name] ||= "prepopulate_fetched_#{association}"

        self.class_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
          attr_reader :#{options[:ids_variable_name]}

          def #{options[:cached_ids_name]}
            #{options[:population_method_name]} unless @#{options[:ids_variable_name]}
            @#{options[:ids_variable_name]}
          end

          def #{options[:population_method_name]}
            @#{options[:ids_variable_name]} = #{options[:ids_name]}
            association_cache.delete(:#{association})
          end

          def #{options[:cached_accessor_name]}
            if IdentityCache.should_cache? || #{association}.loaded?
              #{options[:population_method_name]} unless @#{options[:ids_variable_name]} || @#{options[:records_variable_name]}
              @#{options[:records_variable_name]} ||= #{options[:association_class]}.fetch_multi(*@#{options[:ids_variable_name]})
            else
              #{association}
            end
          end

          def #{options[:prepopulate_method_name]}(records)
            @#{options[:records_variable_name]} = records
          end
        CODE

        add_parent_expiry_hook(options.merge(:only_on_foreign_key_change => true))
      end

      def attribute_dynamic_fetcher(attribute, fields, values) #:nodoc:
        cache_key = rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values)
        sql_on_miss = "SELECT #{connection.quote_column_name(attribute)} FROM #{quoted_table_name} WHERE #{identity_cache_sql_conditions(fields, values)} LIMIT 1"
        IdentityCache.fetch(cache_key) { connection.select_value(sql_on_miss) }
      end

      def add_parent_expiry_hook(options)
        child_class = options[:association_class]
        child_association = child_class.reflect_on_association(options[:inverse_name])
        raise InverseAssociationError unless child_association
        foreign_key = child_association.association_foreign_key
        parent_class ||= self.name

        child_class.send(:include, ArTransactionChanges) unless child_class.include?(ArTransactionChanges)
        child_class.send(:include, ParentModelExpiration) unless child_class.include?(ParentModelExpiration)

        child_class.class_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
          after_commit :expire_parent_cache
          after_touch  :expire_parent_cache

          def expire_parent_cache
            expire_parent_cache_on_changes(:#{options[:inverse_name]}, '#{foreign_key}', #{parent_class}, #{options[:only_on_foreign_key_change]})
          end
        CODE
      end

      def identity_cache_sql_conditions(fields, values)
        fields.each_with_index.collect { |f, i| "#{connection.quote_column_name(f)} = #{quote_value(values[i],nil)}" }.join(" AND ")
      end
    end
  end
end
