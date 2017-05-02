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
    Kernel.load(File.expand_path('../../helpers/models.rb', __FILE__))
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
    Object.send :remove_const, 'SelfItem'
    Object.send :remove_const, 'SelfItemTwo'
    Object.send :remove_const, 'KeyedRecord'
    Object.send :remove_const, 'StiRecord'
    Object.send :remove_const, 'StiRecordTypeA'
    Deeply::Nested.send :remove_const, 'AssociatedRecord'
    Deeply.send :remove_const, 'Nested'
    Object.send :remove_const, 'Deeply'
    IdentityCache.const_get(:ParentModelExpiration).send(:lazy_hooks).clear
  end
end
