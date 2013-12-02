module SerializationFormat
  def serialized_record
    AssociatedRecord.cache_has_many :deeply_associated_records, :embed => true
    AssociatedRecord.cache_belongs_to :item, :embed => false
    Item.cache_has_many :associated_records, :embed => true
    Item.cache_has_one :associated

    record = Item.new(:title => 'foo')
    record.associated_records << AssociatedRecord.new(:name => 'bar')
    record.associated_records << AssociatedRecord.new(:name => 'baz')
    record.associated = AssociatedRecord.new(:name => 'bork')
    record.not_cached_records << NotCachedRecord.new(:name => 'NoCache')
    record.associated.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "corge")
    record.associated.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "qux")
    record.created_at = DateTime.new
    record.save
    Item.update_all("updated_at='#{record.created_at}'", "id='#{record.id}'")
    record.reload
    Item.fetch(record.id)
    IdentityCache.fetch(record.primary_cache_index_key)
  end

  def serialized_record_file
    File.expand_path("../../fixtures/serialized_record", __FILE__)
  end

  def serialize(record, anIO = nil)
    hash = {
      :version => IdentityCache::CACHE_VERSION,
      :record => record
    }
    if anIO
      Marshal.dump(hash, anIO)
    else
      Marshal.dump(hash)
    end
  end
end
