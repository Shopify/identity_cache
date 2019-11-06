module SerializationFormat
  def serialized_record
    AssociatedRecord.cache_has_many(:deeply_associated_records, :embed => true)
    AssociatedRecord.cache_belongs_to(:item)
    Item.cache_has_many(:associated_records, :embed => true)
    Item.cache_has_one(:associated)
    time = Time.parse('1970-01-01T00:00:00 UTC')

    record = Item.new(:title => 'foo')
    record.associated_records << AssociatedRecord.new(:name => 'bar')
    record.associated_records << AssociatedRecord.new(:name => 'baz')
    record.associated = AssociatedRecord.new(:name => 'bork')
    record.not_cached_records << NotCachedRecord.new(:name => 'NoCache', created_at: time)
    record.associated.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "corge", created_at: time)
    record.associated.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "qux", created_at: time)
    record.created_at = time
    record.save
    [Item, NotCachedRecord, DeeplyAssociatedRecord].each do |model|
      model.update_all(updated_at: time)
    end
    record.reload
    Item.fetch(record.id)

    IdentityCache.fetch(record.primary_cache_index_key) do
      STDERR.puts(
        "\e[31m" \
          "The record could not be retrieved from the cache." \
          "Did you configure MEMCACHED_HOST?" \
          "\e[0m",
      )
      exit(1)
    end
  end

  def serialized_record_file
    File.expand_path("../../fixtures/serialized_record.#{DatabaseConnection.db_name}", __FILE__)
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
