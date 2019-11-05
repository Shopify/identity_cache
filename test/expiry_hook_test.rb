require "test_helper"

module IdentityCache
  class ExpiryHookTest < IdentityCache::TestCase
    def test_cached_association
      hook = ExpiryHook.new(reference_cached_association)

      assert_same reference_cached_association, hook.cached_association
    end

    def test_only_on_foreign_key_change_true_when_reference_association
      hook = ExpiryHook.new(reference_cached_association)

      assert_predicate hook, :only_on_foreign_key_change?
    end

    def test_only_on_foreign_key_change_false_when_recursive_association
      hook = ExpiryHook.new(recursive_cached_association)

      refute_predicate hook, :only_on_foreign_key_change?
    end

    def test_only_on_foreign_key_change_false_when_belongs_to
      hook = ExpiryHook.new(belongs_to_reference_cached_association)

      refute_predicate hook, :only_on_foreign_key_change?
    end

    private

    def reference_cached_association
      @reference_assocaition ||= Cached::Reference::HasMany.new(
        :deeply_associated_records,
        inverse_name: :associated_record,
        reflection: reflect(AssociatedRecord, :deeply_associated_records),
      )
    end

    def recursive_cached_association
      @recursive_association ||= Cached::Recursive::HasMany.new(
        :deeply_associated_records,
        inverse_name: :associated_record,
        reflection: reflect(AssociatedRecord, :deeply_associated_records),
      )
    end

    def belongs_to_reference_cached_association
      @reference_assocaition ||= Cached::Reference::BelongsTo.new(
        :item,
        reflection: reflect(AssociatedRecord, :item),
      )
    end
  end
end
