class DeeplyAssociatedRecord < ActiveRecord::Base
  include IdentityCache
  belongs_to :item
  belongs_to :associated_record
  default_scope { order('name DESC') }
end

class AssociatedRecord < ActiveRecord::Base
  include IdentityCache
  belongs_to :item, inverse_of: :associated_records
  belongs_to :item_two, inverse_of: :associated_records
  has_many :deeply_associated_records
  default_scope { order('id DESC') }
end

class NormalizedAssociatedRecord < ActiveRecord::Base
  include IdentityCache
  belongs_to :item
  default_scope { order('id DESC') }
end

class NotCachedRecord < ActiveRecord::Base
  belongs_to :item, :touch => true
  default_scope { order('id DESC') }
end

class PolymorphicRecord < ActiveRecord::Base
  belongs_to :owner, :polymorphic => true
end

class NoInverseOfRecord < ActiveRecord::Base
  include IdentityCache
  belongs_to :owner
end

module Deeply
  module Nested
    class AssociatedRecord < ActiveRecord::Base
      include IdentityCache
    end
  end
end

class Item < ActiveRecord::Base
  include IdentityCache
  belongs_to :item
  has_many :associated_records, inverse_of: :item
  has_many :deeply_associated_records, inverse_of: :item
  has_many :normalized_associated_records
  has_many :not_cached_records
  has_many :polymorphic_records, :as => 'owner'
  has_many :no_inverse_of_records
  has_one :polymorphic_record, :as => 'owner'
  has_one :associated, :class_name => 'AssociatedRecord'
  has_one :no_inverse_of_record
end

class ItemTwo < ActiveRecord::Base
  include IdentityCache
  has_many :associated_records, inverse_of: :item_two, foreign_key: :item_two_id
  self.table_name = 'items2'
end

class KeyedRecord < ActiveRecord::Base
  include IdentityCache
  self.primary_key = "hashed_key"
end

class StiRecord < ActiveRecord::Base
  include IdentityCache
  has_many :polymorphic_records, :as => 'owner'
end

class StiRecordTypeA < StiRecord
end

class CustomMasterRecord < ActiveRecord::Base
  include IdentityCache
  has_many :custom_child_record, foreign_key: :master_id
  self.primary_key = 'master_primary_key'
end

class CustomChildRecord < ActiveRecord::Base
  include IdentityCache
  belongs_to :custom_master_record, foreign_key: :master_id
  self.primary_key = 'child_primary_key'
end
