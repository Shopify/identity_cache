# frozen_string_literal: true
module SwitchNamespace

  module ClassMethods
    def rails_cache_key_namespace
      "#{namespace}:#{super}"
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
    base.class_eval do
      class_attribute :namespace
      self.namespace = 'ns'
    end
  end
end

module ActiveRecordObjects
  def setup_models
    Kernel.load(File.expand_path('../../helpers/models.rb', __FILE__))
    include_idc_into_associated_record
  end

  def include_idc_into_associated_record
    AssociatedRecord.include(IdentityCache)
  end

  def teardown_models
    ActiveSupport::DescendantsTracker.clear
    ActiveSupport::Dependencies.clear
    Object.send(:remove_const, 'DeeplyAssociatedRecord')
    Object.send(:remove_const, 'PolymorphicRecord')
    Object.send(:remove_const, 'NormalizedAssociatedRecord')
    Object.send(:remove_const, 'AssociatedRecord')
    Object.send(:remove_const, 'NotCachedRecord')
    Object.send(:remove_const, 'NoInverseOfRecord')
    Object.send(:remove_const, 'Item')
    Object.send(:remove_const, 'ItemTwo')
    Object.send(:remove_const, 'KeyedRecord')
    Object.send(:remove_const, 'StiRecord')
    Object.send(:remove_const, 'StiRecordTypeA')
    Deeply::Nested.send(:remove_const, 'AssociatedRecord')
    Deeply.send(:remove_const, 'Nested')
    Object.send(:remove_const, 'Deeply')
    Object.send(:remove_const, 'CustomMasterRecord')
    Object.send(:remove_const, 'CustomChildRecord')
    IdentityCache.const_get(:ParentModelExpiration).send(:lazy_hooks).clear
  end
end
