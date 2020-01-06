module LazyModel
  class B < ActiveRecord::Base
    self.table_name = "lazy_bs"
    include IdentityCache
    belongs_to :a, class_name: "::LazyModel::A", inverse_of: :bs
    has_one :c, class_name: "::LazyModel::C", inverse_of: :b
    cache_has_one :c
  end
end
