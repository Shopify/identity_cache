require "test_helper"

class CacheFetchIncludesTest < IdentityCache::TestCase
  def setup
    super
  end

  def test_cached_embedded_has_manys_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    assert_equal [:associated_records], Item.send(:cache_fetch_includes)
  end

  def test_cached_nonembedded_has_manys_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :ids)
    assert_equal [], Item.send(:cache_fetch_includes)
  end

  def test_cached_has_ones_are_included_in_includes
    Item.send(:cache_has_one, :associated)
    assert_equal [:associated], Item.send(:cache_fetch_includes)
  end

  def test_cached_nonembedded_belongs_tos_are_not_included_in_includes
    Item.send(:cache_belongs_to, :item)
    assert_equal [], Item.send(:cache_fetch_includes)
  end

  def test_cached_child_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => :recursively)
    assert_equal [{:associated_records => [:deeply_associated_records]}], Item.send(:cache_fetch_includes)
  end

  def test_multiple_cached_associations_and_child_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    Item.send(:cache_has_many, :polymorphic_records, {:inverse_name => :owner, :embed => :recursively})
    Item.send(:cache_has_one, :associated, :embed => :recursively)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => :recursively)
    assert_equal [
      {:associated_records => [:deeply_associated_records]},
      :polymorphic_records,
      {:associated => [:deeply_associated_records]}
    ],  Item.send(:cache_fetch_includes)
  end

  def test_empty_additions_for_top_level_associations_makes_no_difference
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    assert_equal [:associated_records], Item.send(:cache_fetch_includes, {})
  end

  def test_top_level_additions_are_included_in_includes
    assert_equal [{:associated_records => []}], Item.send(:cache_fetch_includes, {:associated_records => []})
  end

  def test_top_level_additions_alongside_top_level_cached_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    assert_equal [
      :associated_records,
      {:polymorphic_records => []}
    ], Item.send(:cache_fetch_includes, {:polymorphic_records => []})
  end

  def test_child_level_additions_for_top_level_cached_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    assert_equal [
      {:associated_records => [{:deeply_associated_records => []}]}
    ], Item.send(:cache_fetch_includes, {:associated_records => :deeply_associated_records})
  end

  def test_array_child_level_additions_for_top_level_cached_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    assert_equal [
      {:associated_records => [{:deeply_associated_records => []}]}
    ], Item.send(:cache_fetch_includes, {:associated_records => [:deeply_associated_records]})
  end

  def test_array_child_level_additions_for_child_level_cached_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, :embed => :recursively)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => :recursively)
    assert_equal [
      {:associated_records => [
        :deeply_associated_records,
        {:record => []}
      ]}
    ], Item.send(:cache_fetch_includes, {:associated_records => [:record]})
  end

end
