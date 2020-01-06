module LazyModel
  class C < ActiveRecord::Base
    self.table_name = "lazy_cs"
    include IdentityCache
    belongs_to :b, class_name: "::LazyModel::B", inverse_of: :c
  end
end
