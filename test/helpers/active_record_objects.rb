module ActiveRecordObjects
  def setup_models(base = ActiveRecord::Base)
    Object.send :const_set, 'DeeplyAssociatedRecord', Class.new(base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :associated_record
    }

    Object.send :const_set, 'AssociatedRecord', Class.new(base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :record
      klass.has_many :deeply_associated_records, :order => "name DESC"
    }

    Object.send :const_set, 'NotCachedRecord', Class.new(base).tap {|klass|
      klass.belongs_to :record, :touch => true
    }

    Object.send :const_set, 'PolymorphicRecord', Class.new(base).tap {|klass|
      klass.belongs_to :owner, :polymorphic => true
    }

    Object.send :const_set, 'Record', Class.new(base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :record
      klass.has_many :associated_records, :order => "id DESC"
      klass.has_many :not_cached_records, :order => "id DESC"
      klass.has_many :polymorphic_records, :as => 'owner'
      klass.has_one :polymorphic_record, :as => 'owner'
      klass.has_one :associated, :class_name => 'AssociatedRecord', :order => "id ASC"
    }
  end

  def teardown_models
    ActiveSupport::DescendantsTracker.clear
    ActiveSupport::Dependencies.clear
    Object.send :remove_const, 'DeeplyAssociatedRecord'
    Object.send :remove_const, 'PolymorphicRecord'
    Object.send :remove_const, 'AssociatedRecord'
    Object.send :remove_const, 'NotCachedRecord'
    Object.send :remove_const, 'Record'
  end
end

