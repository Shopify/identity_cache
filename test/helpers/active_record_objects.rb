module SwitchNamespace

  module ClassMethods
    def rails_cache_key_namespace
      "#{self.namespace}:#{super}"
    end
  end

  def self.included(base)
    base.extend ClassMethods
    base.class_eval do
      class_attribute :namespace
      self.namespace = 'ns'
    end
  end
end

module ActiveRecordObjects

  def setup_models(base = ActiveRecord::Base)
    Object.send :const_set, 'DeeplyAssociatedRecord', Class.new(base) {
      include IdentityCache
      belongs_to :item
      belongs_to :associated_record
      default_scope { order('name DESC') }
    }

    Object.send :const_set, 'AssociatedRecord', Class.new(base) {
      include IdentityCache
      belongs_to :item, inverse_of: :associated_records
      belongs_to :item_two, inverse_of: :associated_records
      has_many :deeply_associated_records
      default_scope { order('id DESC') }
    }

    Object.send :const_set, 'NormalizedAssociatedRecord', Class.new(base) {
      include IdentityCache
      belongs_to :item
      default_scope { order('id DESC') }
    }

    Object.send :const_set, 'NotCachedRecord', Class.new(base) {
      belongs_to :item, :touch => true
      default_scope { order('id DESC') }
    }

    Object.send :const_set, 'PolymorphicRecord', Class.new(base) {
      belongs_to :owner, :polymorphic => true
    }

    Object.send :const_set, 'Deeply', Module.new
    Deeply.send :const_set, 'Nested', Module.new
    Deeply::Nested.send :const_set, 'AssociatedRecord', Class.new(base) {
      include IdentityCache
    }

    Object.send :const_set, 'Item', Class.new(base) {
      include IdentityCache
      belongs_to :item
      has_many :associated_records, inverse_of: :item
      has_many :deeply_associated_records, inverse_of: :item
      has_many :normalized_associated_records
      has_many :not_cached_records
      has_many :polymorphic_records, :as => 'owner'
      has_one :polymorphic_record, :as => 'owner'
      has_one :associated, :class_name => 'AssociatedRecord'
    }

    Object.send :const_set, 'ItemTwo', Class.new(base) {
      include IdentityCache
      has_many :associated_records, inverse_of: :item_two, foreign_key: :item_two_id
      self.table_name = 'items2'
    }

    Object.send :const_set, 'KeyedRecord', Class.new(base) {
      include IdentityCache
      self.primary_key = "hashed_key"
    }
  end

  def teardown_models
    ActiveSupport::DescendantsTracker.clear
    ActiveSupport::Dependencies.clear
    Object.send :remove_const, 'DeeplyAssociatedRecord'
    Object.send :remove_const, 'PolymorphicRecord'
    Object.send :remove_const, 'NormalizedAssociatedRecord'
    Object.send :remove_const, 'AssociatedRecord'
    Object.send :remove_const, 'NotCachedRecord'
    Object.send :remove_const, 'Item'
    Object.send :remove_const, 'ItemTwo'
    Object.send :remove_const, 'KeyedRecord'
    Deeply::Nested.send :remove_const, 'AssociatedRecord'
    Deeply.send :remove_const, 'Nested'
    Object.send :remove_const, 'Deeply'
  end
end
