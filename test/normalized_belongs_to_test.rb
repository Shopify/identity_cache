require "test_helper"

class NormalizedBelongsToTest < IdentityCache::TestCase
  def setup
    super
    AssociatedRecord.cache_belongs_to :record, :embed => false

    @parent_record = Record.new(:title => 'foo')
    @parent_record.associated_records << AssociatedRecord.new(:name => 'bar')
    @parent_record.save
    @parent_record.reload
    @record = @parent_record.associated_records.first
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_any_transactions_are_open
    Record.expects(:fetch_by_id).never
    @record.transaction do
      assert_equal @parent_record, @record.fetch_record
    end
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_the_normal_association_is_loaded
    # Warm the ActiveRecord association
    @record.record

    Record.expects(:fetch_by_id).never
    assert_equal @parent_record, @record.fetch_record
  end

  def test_fetching_the_association_should_fetch_the_record_from_identity_cache
    Record.expects(:fetch_by_id).with(@parent_record.id).returns(@parent_record)
    assert_equal @parent_record, @record.fetch_record
  end

  def test_fetching_the_association_should_assign_the_result_to_the_association_so_that_successive_accesses_are_cached
    Record.expects(:fetch_by_id).with(@parent_record.id).returns(@parent_record)
    @record.fetch_record
    assert @record.association(:record).loaded?
    assert_equal @parent_record, @record.record
  end

  def test_fetching_the_association_shouldnt_raise_if_the_record_cant_be_found
    Record.expects(:fetch_by_id).with(@parent_record.id).returns(nil)
    assert_equal nil, @record.fetch_record
  end

  def test_returned_record_should_be_readonly_on_cache_hit
    Record.fetch(@parent_record.id) # warm cache
    assert @record.fetch_record.readonly?
  end

  def test_returned_record_should_be_readonly_on_cache_miss
    assert @record.fetch_record.readonly?
  end

  def test_returned_record_with_open_transactions_should_be_readonly
    Record.transaction do
      assert @record.fetch_record.readonly?
    end
  end
end
