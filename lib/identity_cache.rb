require "identity_cache/version"
require 'cityhash'
require 'ar_transaction_changes'
require File.dirname(__FILE__) + '/memoized_cache_proxy'
require File.dirname(__FILE__) + '/belongs_to_caching'

module IdentityCache
  CACHED_NIL = :idc_cached_nil

  class << self

    attr_accessor :logger, :readonly
    attr_reader :cache

    # Sets the cache adaptor IdentityCache will be using
    #
    # == Parameters
    #
    # +cache_adaptor+ - A ActiveSupport::Cache::Store
    #
    def cache_backend=(cache_adaptor)
      cache.memcache = cache_adaptor
    end

    def cache
      @cache ||= MemoizedCacheProxy.new
    end

    def logger
      @logger || Rails.logger
    end

    def should_cache?
      !readonly && ActiveRecord::Base.connection.open_transactions == 0
    end

    # Cache retrieval and miss resolver primitive, given a key it will try to
    # retrieve the associated value from the cache otherwise it will return the
    # value of the execution of the block.
    #
    # == Parameters
    # +key+ A cache key string
    #
    def fetch(key, &block)
      result = cache.read(key) if should_cache?

      if result.nil?
        if block_given?
          ActiveRecord::Base.connection.with_master do
            result = yield
          end
          result = map_cached_nil_for(result)
          if should_cache?
            cache.write(key, result)
          end
        end
        logger.debug "[IdentityCache] cache miss for #{key}"
      else
        logger.debug "[IdentityCache] cache hit for #{key}"
      end

      unmap_cached_nil_for(result)
    end

    def map_cached_nil_for(value)
      value.nil? ? IdentityCache::CACHED_NIL : value
    end


    def unmap_cached_nil_for(value)
      value == IdentityCache::CACHED_NIL ? nil : value
    end

    # Same as +fetch+, except that it will try a collection of keys, using the
    # multiget operation of the cache adaptor
    #
    # == Parameters
    # +keys+ A collection of key strings
    def fetch_multi(*keys, &block)
      return {} if keys.size == 0
      result = {}
      result = cache.read_multi(*keys) if should_cache?

      missed_keys = keys - result.select {|key, value| value.present? }.keys

      if missed_keys.size > 0
        if block_given?
          replacement_results = nil
          ActiveRecord::Base.connection.with_master do
            replacement_results = yield missed_keys
          end
          missed_keys.zip(replacement_results) do |(key, replacement_result)|
            if should_cache?
              replacement_result  = map_cached_nil_for(replacement_result )
              cache.write(key, replacement_result)
              logger.debug "[IdentityCache] cache miss for #{key} (multi)"
            end
            result[key] = replacement_result
          end
        end
      else
        result.keys.each do |key|
          logger.debug "[IdentityCache] cache hit for #{key} (multi)"
        end
      end

      result.keys.each do |key|
        result[key] = unmap_cached_nil_for(result[key])
      end

      result
    end

    def included(base) #:nodoc:
      raise AlreadyIncludedError if base.respond_to? :cache_indexes

      unless ActiveRecord::Base.connection.respond_to?(:with_master)
        ActiveRecord::Base.connection.class.class_eval(ruby = <<-CODE, __FILE__, __LINE__)
          def with_master
            yield
          end
        CODE
      end

      base.send(:include, ArTransactionChanges) unless base.include?(ArTransactionChanges)
      base.send(:include, IdentityCache::BelongsToCaching)
      base.after_commit :expire_cache
      base.after_touch  :expire_cache
      base.class_attribute :cache_indexes
      base.class_attribute :cache_attributes
      base.class_attribute :cached_has_manys
      base.class_attribute :cached_has_ones
      base.send(:extend, ClassMethods)

      base.private_class_method :require_if_necessary, :build_normalized_has_many_cache, :build_denormalized_association_cache, :add_parent_expiry_hook,
        :identity_cache_multiple_value_dynamic_fetcher, :identity_cache_single_value_dynamic_fetcher

      base.instance_eval(ruby = <<-CODE, __FILE__, __LINE__)
        private :expire_cache, :was_new_record?, :fetch_denormalized_cached_association, :populate_denormalized_cached_association
      CODE
    end

    def memcache_hash(key) #:nodoc:
      CityHash.hash64(key)
    end
  end

  module ClassMethods

    # Declares a new index in the cache for the class where IdentityCache was
    # included, this will have two important consequences.
    # 
    # * IdentityCache will add a fetch_by_field1_and_field2_and_...fieldn where
    # * Those methods will expect index keys in the cache, and create them on
    #    reads to the cache values
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
    # * Unique: if the index would only have unique values
    #  
    def cache_index(*fields)
      options = fields.extract_options!
      self.cache_indexes ||= []
      self.cache_indexes.push fields

      field_list = fields.join("_and_")
      arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')
      where_list = fields.each_with_index.collect { |f, i| "#{f} = \#{quote_value(arg#{i})}" }.join(" AND ")

      if options[:unique]
        self.instance_eval(ruby = <<-CODE, __FILE__, __LINE__)
          def fetch_by_#{field_list}(#{arg_list})
            sql = "SELECT id FROM #{table_name} WHERE #{where_list} LIMIT 1"
            identity_cache_single_value_dynamic_fetcher(#{fields.inspect}, [#{arg_list}], sql)
          end

          # exception throwing variant
          def fetch_by_#{field_list}!(#{arg_list})
            fetch_by_#{field_list}(#{arg_list}) or raise ActiveRecord::RecordNotFound
          end
        CODE
      else
        self.instance_eval(ruby = <<-CODE, __FILE__, __LINE__)
          def fetch_by_#{field_list}(#{arg_list})
            sql = "SELECT id FROM #{table_name} WHERE #{where_list}"
            identity_cache_multiple_value_dynamic_fetcher(#{fields.inspect}, [#{arg_list}], sql)
          end
        CODE
      end
    end

    def identity_cache_single_value_dynamic_fetcher(fields, values, sql_on_miss) # :nodoc:
      cache_key = rails_cache_index_key_for_fields_and_values(fields, values)
      id = IdentityCache.fetch(cache_key) { connection.select_value(sql_on_miss) }
      unless id.nil?
        record = fetch_by_id(id.to_i)
        IdentityCache.cache.delete(cache_key) unless record
      end

      record
    end

    def identity_cache_multiple_value_dynamic_fetcher(fields, values, sql_on_miss) # :nodoc:
      cache_key = rails_cache_index_key_for_fields_and_values(fields, values)
      ids = IdentityCache.fetch(cache_key) { connection.select_values(sql_on_miss) }

      ids.empty? ? [] : fetch_multi(*ids)
    end


    # Will cache an association to the class including IdentityCache,
    # the embed option if set will make IdentityCache keep the association
    # values in the same cache entry as the parent.
    #
    # Embedded associations are more effective in offloading database work,
    # however they will increase the size of the cache entries and make the
    # whole entry expire with the change of any of the embedded members
    #
    # == Example:
    #   class Product
    #    cached_has_many :options, :embed => false
    #    cached_has_many :orders
    #    cached_has_many :buyers, :inverse_name => 'line_item'
    #   end
    #
    # == Parameters
    # +association+ Symbol with the name of the association being cached
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
      self.cached_has_manys ||= {}
      self.cached_has_manys[association] = options

      if options[:embed]
        build_denormalized_association_cache(association, options)
      else
        build_normalized_has_many_cache(association, options)
      end
    end

    # Will cache an association to the class including IdentityCache,
    # the embed option if set will make IdentityCache keep the association
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
    # * inverse_name: The name of the parent in the association if the name is
    #   not the lowercase pluralization of the parent object's class
    def cache_has_one(association, options = {})
      options[:embed] ||= true
      options[:inverse_name] ||= self.name.underscore.to_sym
      raise InverseAssociationError unless self.reflect_on_association(association)
      self.cached_has_ones ||= {}
      self.cached_has_ones[association] = options

      build_denormalized_association_cache(association, options)
    end

    def build_denormalized_association_cache(association, options) #:nodoc:
      options[:cached_accessor_name] ||= "fetch_#{association}"
      options[:cache_variable_name]  ||= "cached_#{association}"
      options[:population_method_name]  ||= "populate_#{association}_cache"

      unless instance_methods.include?(options[:cached_accessor_name].to_sym)
        self.class_eval(ruby = <<-CODE, __FILE__, __LINE__)
          def #{options[:cached_accessor_name]}
            fetch_denormalized_cached_association('#{options[:cache_variable_name]}', :#{association})
          end

          def #{options[:population_method_name]}
            populate_denormalized_cached_association('#{options[:cache_variable_name]}', :#{association})
          end
        CODE

        association_class = reflect_on_association(association).klass
        add_parent_expiry_hook(association_class, options.merge(:only_on_foreign_key_change => false))
      end
    end

    def build_normalized_has_many_cache(association, options) #:nodoc:
      singular_association = association.to_s.singularize
      association_class    = reflect_on_association(association).klass
      options[:cached_accessor_name]    ||= "fetch_#{association}"
      options[:ids_name]                ||= "#{singular_association}_ids"
      options[:ids_cache_name]          ||= "cached_#{options[:ids_name]}"
      options[:population_method_name]  ||= "populate_#{association}_cache"

      self.class_eval(ruby = <<-CODE, __FILE__, __LINE__)
        attr_reader :#{options[:ids_cache_name]}

        def #{options[:population_method_name]}
          @#{options[:ids_cache_name]} = #{options[:ids_name]}
        end

        def #{options[:cached_accessor_name]}
          if IdentityCache.should_cache? || #{association}.loaded?
            populate_#{association}_cache unless @#{options[:ids_cache_name]}
            @cached_#{association} ||= #{association_class}.fetch_multi(*@#{options[:ids_cache_name]})
          else
            #{association}
          end
        end
      CODE

      add_parent_expiry_hook(association_class, options.merge(:only_on_foreign_key_change => true))
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
    # * by: Other attribute or attributes in the model to keep values indexed, default is :id
    def cache_attribute(attribute, options = {})
      options[:by] ||= :id
      fields = Array(options[:by])

      self.cache_attributes ||= []
      self.cache_attributes.push [attribute, fields]

      field_list = fields.join("_and_")
      arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')
      where_list = fields.each_with_index.collect { |f, i| "#{f} = \#{quote_value(arg#{i})}" }.join(" AND ")

      self.instance_eval(ruby = <<-CODE, __FILE__, __LINE__)
        def fetch_#{attribute}_by_#{field_list}(#{arg_list})
          sql = "SELECT #{attribute} FROM #{table_name} WHERE #{where_list} LIMIT 1"
          attribute_dynamic_fetcher(#{attribute.inspect}, #{fields.inspect}, [#{arg_list}], sql)
        end
      CODE
    end

    def attribute_dynamic_fetcher(attribute, fields, values, sql_on_miss) #:nodoc:
      cache_key = rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values)
      IdentityCache.fetch(cache_key) { connection.select_value(sql_on_miss) }
    end

    # Similar to ActiveRecord::Base#exists? will return true if the id can be
    # found in the cache.
    def exists_with_identity_cache?(id)
      !!fetch_by_id(id)
    end

    # Default fetched added to the model on inclusion, it behaves like
    # ActiveRecord::Base.find_by_id
    def fetch_by_id(id)
      if IdentityCache.should_cache?

        require_if_necessary do
          object = IdentityCache.fetch(rails_cache_key(id)){ resolve_cache_miss(id) }
          object.clear_association_cache if object.respond_to?(:clear_association_cache)
          IdentityCache.logger.error "[IDC id mismatch] fetch_by_id_requested=#{id} fetch_by_id_got=#{object.id} for #{object.inspect[(0..100)]} " if object && object.id != id.to_i
          object
        end

      else
        self.find_by_id(id)
      end
    end

    # Default fetched added to the model on inclusion, it behaves like
    # ActiveRecord::Base.find, will raise ActiveRecord::RecordNotFound exception
    # if id is not in the cache or the db.
    def fetch(id)
      fetch_by_id(id) or raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.class.name} with ID=#{id}")
    end


    # Default fetched added to the model on inclusion, if behaves like
    # ActiveRecord::Base.find_all_by_id
    def fetch_multi(*ids)
      if IdentityCache.should_cache?

        require_if_necessary do
          cache_keys = ids.map {|id| rails_cache_key(id) }
          key_to_id_map = Hash[ cache_keys.zip(ids) ]

          objects_by_key = IdentityCache.fetch_multi(*key_to_id_map.keys) do |unresolved_keys|
            ids = unresolved_keys.map {|key| key_to_id_map[key] }
            records = find_batch(ids)
            records.compact.each(&:populate_association_caches)
            records
          end

          objects_in_order = cache_keys.map {|key| objects_by_key[key] }
          objects_in_order.each do |object|
            object.clear_association_cache if object.respond_to?(:clear_association_cache)
          end

          objects_in_order.compact
        end

      else
        find_batch(ids)
      end
    end

    def require_if_necessary #:nodoc:
      # mem_cache_store returns raw value if unmarshal fails
      rval = yield
      case rval
      when String
        rval = Marshal.load(rval)
      when Array
        rval.map!{ |v| v.kind_of?(String) ? Marshal.load(v) : v }
      end
      rval
    rescue ArgumentError => e
      if e.message =~ /undefined [\w\/]+ (\w+)/
        ok = Kernel.const_get($1) rescue nil
        retry if ok
      end
      raise
    end

    module ParentModelExpiration # :nodoc:
      def expire_parent_cache_on_changes(parent_name, foreign_key, parent_class, options = {})
        new_parent = send(parent_name)

        if new_parent && new_parent.respond_to?(:expire_primary_index, true)
          if should_expire_identity_cache_parent?(foreign_key, options[:only_on_foreign_key_change])
            new_parent.expire_primary_index
            new_parent.expire_parent_cache if new_parent.respond_to?(:expire_parent_cache)
          end
        end

        if transaction_changed_attributes[foreign_key].present?
          begin
            old_parent = parent_class.find(transaction_changed_attributes[foreign_key])
            old_parent.expire_primary_index if old_parent.respond_to?(:expire_primary_index)
            old_parent.expire_parent_cache  if old_parent.respond_to?(:expire_parent_cache)
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

    def add_parent_expiry_hook(child_class, options = {})
      child_association = child_class.reflect_on_association(options[:inverse_name])
      raise InverseAssociationError unless child_association
      foreign_key = child_association.association_foreign_key
      parent_class ||= self.name
      new_parent = options[:inverse_name]

      child_class.send(:include, ArTransactionChanges) unless child_class.include?(ArTransactionChanges)
      child_class.send(:include, ParentModelExpiration) unless child_class.include?(ParentModelExpiration)

      child_class.class_eval(ruby = <<-CODE, __FILE__, __LINE__)
        after_commit :expire_parent_cache
        after_touch  :expire_parent_cache

        def expire_parent_cache
          expire_parent_cache_on_changes(:#{options[:inverse_name]}, '#{foreign_key}', #{parent_class}, #{options.inspect})
        end
      CODE
    end

    def resolve_cache_miss(id)
      self.find_by_id(id, :include => cache_fetch_includes).tap do |object|
        object.try(:populate_association_caches)
      end
    end

    def all_cached_associations
      (cached_has_manys || {}).merge(cached_has_ones || {})
    end

    def cache_fetch_includes
      all_cached_associations.select{|k, v| v[:embed]}.map do |child_association, options|
        child_class = reflect_on_association(child_association).try(:klass)
        child_includes = child_class.respond_to?(:cache_fetch_includes) ? child_class.cache_fetch_includes : []
        if child_includes.empty?
          child_association
        else
          { child_association => child_class.cache_fetch_includes }
        end
      end
    end

    def find_batch(ids)
      @id_column ||= columns.detect {|c| c.name == "id"}
      ids = ids.map{ |id| @id_column.type_cast(id) }
      records = where('id IN (?)', ids).includes(cache_fetch_includes).all
      records_by_id = records.index_by(&:id)
      records = ids.map{ |id| records_by_id[id] }
      mismatching_ids = records.compact.map(&:id) - ids
      IdentityCache.logger.error "[IDC id mismatch] fetch_batch_requested=#{ids.inspect} fetch_batch_got=#{mismatchig_ids.inspect} mismatching ids "  unless mismatching_ids.empty?
      records
    end

    def rails_cache_key(id)
      rails_cache_key_prefix + id.to_s
    end

    def rails_cache_key_prefix
      @rails_cache_key_prefix ||= begin
        column_list = columns.sort_by(&:name).map {|c| "#{c.name}:#{c.type}"} * ","
        "IDC:blob:#{base_class.name}:#{IdentityCache.memcache_hash(column_list)}:"
      end
    end

    def rails_cache_index_key_for_fields_and_values(fields, values)
      "IDC:index:#{base_class.name}:#{rails_cache_string_for_fields_and_values(fields, values)}"
    end

    def rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values)
      "IDC:attribute:#{base_class.name}:#{attribute}:#{rails_cache_string_for_fields_and_values(fields, values)}"
    end

    def rails_cache_string_for_fields_and_values(fields, values)
      "#{fields.join('/')}:#{IdentityCache.memcache_hash(values.join('/'))}"
    end
  end

  def populate_association_caches
    self.class.all_cached_associations.each do |cached_association, options|
      send(options[:population_method_name])
      reflection = options[:embed] && self.class.reflect_on_association(cached_association)
      if reflection && reflection.klass.respond_to?(:cached_has_manys)
        child_objects = Array.wrap(send(options[:cached_accessor_name]))
        child_objects.each(&:populate_association_caches)
      end
    end
  end

  def fetch_denormalized_cached_association(ivar_name, association_name)
    ivar_full_name = :"@#{ivar_name}"
    if IdentityCache.should_cache?
      populate_denormalized_cached_association(ivar_name, association_name)
      IdentityCache.unmap_cached_nil_for(instance_variable_get(ivar_full_name))
    else
      send(association_name.to_sym)
    end
  end

  def populate_denormalized_cached_association(ivar_name, association_name)
    ivar_full_name = :"@#{ivar_name}"

    value = instance_variable_get(ivar_full_name)
    return value unless value.nil?

    reflection = association(association_name)
    reflection.load_target unless reflection.loaded?

    loaded_association = send(association_name)
    instance_variable_set(ivar_full_name, IdentityCache.map_cached_nil_for(loaded_association))
  end

  def primary_cache_index_key
    self.class.rails_cache_key(id)
  end

  def secondary_cache_index_key_for_current_values(fields)
    self.class.rails_cache_index_key_for_fields_and_values(fields, fields.collect {|field| self.send(field)})
  end

  def secondary_cache_index_key_for_previous_values(fields)
    self.class.rails_cache_index_key_for_fields_and_values(fields, old_values_for_fields(fields))
  end

  def attribute_cache_key_for_attribute_and_previous_values(attribute, fields)
    self.class.rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, old_values_for_fields(fields))
  end

  def old_values_for_fields(fields)
    fields.map do |field|
      field_string = field.to_s
      if destroyed? && transaction_changed_attributes.has_key?(field_string)
        transaction_changed_attributes[field_string]
      elsif persisted? && transaction_changed_attributes.has_key?(field_string)
        transaction_changed_attributes[field_string]
      else
        self.send(field)
      end
    end
  end

  def expire_primary_index
    extra_keys = if respond_to? :updated_at
      old_updated_at = old_values_for_fields([:updated_at]).first
      "expiring_last_updated_at=#{old_updated_at}"
    else
      ""
    end
    IdentityCache.logger.debug "[IdentityCache] expiring=#{self.class.name} expiring_id=#{id} #{extra_keys}"

    IdentityCache.cache.delete(primary_cache_index_key)
  end

  def expire_secondary_indexes
    cache_indexes.try(:each) do |fields|
      if self.destroyed?
        IdentityCache.cache.delete(secondary_cache_index_key_for_previous_values(fields))
      else
        new_cache_index_key = secondary_cache_index_key_for_current_values(fields)
        IdentityCache.cache.delete(new_cache_index_key)

        if !was_new_record?
          old_cache_index_key = secondary_cache_index_key_for_previous_values(fields)
          IdentityCache.cache.delete(old_cache_index_key) unless old_cache_index_key == new_cache_index_key
        end
      end
    end
  end

  def expire_attribute_indexes
    cache_attributes.try(:each) do |(attribute, fields)|
      IdentityCache.cache.delete(attribute_cache_key_for_attribute_and_previous_values(attribute, fields)) unless was_new_record?
    end
  end

  def expire_cache
    expire_primary_index
    expire_secondary_indexes
    expire_attribute_indexes
    true
  end

  def was_new_record?
    !destroyed? && transaction_changed_attributes.has_key?('id') && transaction_changed_attributes['id'].nil?
  end

  class AlreadyIncludedError < StandardError; end
  class InverseAssociationError < StandardError
    def initialize
      super "Inverse name for association could not be determined. Please use the :inverse_name option to specify the inverse association name for this cache."
    end
  end
end
