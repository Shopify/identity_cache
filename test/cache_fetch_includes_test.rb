require "test_helper"

class CacheFetchIncludesTest < IdentityCache::TestCase
  def setup
    super
  end

  def test_cached_embedded_has_manys_are_included_in_includes
    Record.send(:cache_has_many, :associated_records, :embed => true)
    assert_equal [:associated_records], Record.cache_fetch_includes
  end

  def test_cached_nonembedded_has_manys_are_included_in_includes
    Record.send(:cache_has_many, :associated_records, :embed => false)
    assert_equal [], Record.cache_fetch_includes
  end

  def test_cached_has_ones_are_included_in_includes
    Record.send(:cache_has_one, :associated)
    assert_equal [:associated], Record.cache_fetch_includes
  end

  def test_cached_nonembedded_belongs_tos_are_not_included_in_includes
    Record.send(:cache_belongs_to, :record)
    assert_equal [], Record.cache_fetch_includes
  end

  def test_cached_child_associations_are_included_in_includes
    Record.send(:cache_has_many, :associated_records, :embed => true)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => true)
    assert_equal [{:associated_records => [:deeply_associated_records]}], Record.cache_fetch_includes
  end

  def test_multiple_cached_associations_and_child_associations_are_included_in_includes
    Record.send(:cache_has_many, :associated_records, :embed => true)
    Record.send(:cache_has_many, :polymorphic_records, {:inverse_name => :owner, :embed => true})
    Record.send(:cache_has_one, :associated, :embed => true)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => true)
    assert_equal [
      {:associated_records => [:deeply_associated_records]},
      :polymorphic_records,
      {:associated => [:deeply_associated_records]}
    ],  Record.cache_fetch_includes
  end

end
