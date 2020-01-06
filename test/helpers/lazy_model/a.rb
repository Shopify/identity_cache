module LazyModel
  class A < ActiveRecord::Base
    self.table_name = "lazy_as"
    include IdentityCache
    has_many :bs, class_name: "::LazyModel::B"
    cache_has_many :bs, embed: true
  end
end
