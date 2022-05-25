# frozen_string_literal: true

module IdentityCache
  module Encoder
    DEHYDRATE_EVENT = "dehydration.identity_cache"
    HYDRATE_EVENT   = "hydration.identity_cache"

    class << self
      def encode(record)
        return unless record

        ActiveSupport::Notifications.instrument(DEHYDRATE_EVENT, class: record.class.name) do
          coder_from_record(record, record.class)
        end
      end

      def decode(coder, klass)
        return unless coder

        ActiveSupport::Notifications.instrument(HYDRATE_EVENT, class: klass.name) do
          record_from_coder(coder, klass)
        end
      end

      private

      def coder_from_record(record, klass)
        return unless record

        coder = {}
        coder[:attributes] = record.attributes_before_type_cast.dup

        recursively_embedded_associations = klass.send(:recursively_embedded_associations)
        id_embedded_has_manys = klass.cached_has_manys.select { |_, association| association.embedded_by_reference? }
        id_embedded_has_ones = klass.cached_has_ones.select { |_, association| association.embedded_by_reference? }

        if recursively_embedded_associations.present?
          coder[:associations] = recursively_embedded_associations.each_with_object({}) do |(name, association), hash|
            hash[name] = IdentityCache.map_cached_nil_for(embedded_coder(record, name, association))
          end
        end

        if id_embedded_has_manys.present?
          coder[:association_ids] = id_embedded_has_manys.each_with_object({}) do |(name, association), hash|
            hash[name] = record.instance_variable_get(association.ids_variable_name)
          end
        end

        if id_embedded_has_ones.present?
          coder[:association_id] = id_embedded_has_ones.each_with_object({}) do |(name, association), hash|
            hash[name] = record.instance_variable_get(association.id_variable_name)
          end
        end

        coder
      end

      def embedded_coder(record, _association, cached_association)
        embedded_record_or_records = record.public_send(cached_association.cached_accessor_name)

        if embedded_record_or_records.respond_to?(:to_ary)
          embedded_record_or_records.map do |embedded_record|
            coder_from_record(embedded_record, embedded_record.class)
          end
        else
          coder_from_record(embedded_record_or_records, embedded_record_or_records.class)
        end
      end

      def record_from_coder(coder, klass) # :nodoc:
        record = klass.instantiate(coder[:attributes].dup)

        if coder.key?(:associations)
          coder[:associations].each do |name, value|
            record.instance_variable_set(klass.cached_association(name).dehydrated_variable_name, value)
          end
        end
        if coder.key?(:association_ids)
          coder[:association_ids].each do |name, ids|
            record.instance_variable_set(klass.cached_has_manys.fetch(name).ids_variable_name, ids)
          end
        end
        if coder.key?(:association_id)
          coder[:association_id].each do |name, id|
            record.instance_variable_set(klass.cached_has_ones.fetch(name).id_variable_name, id)
          end
        end

        record.readonly! if IdentityCache.fetch_read_only_records
        record
      end
    end
  end

  private_constant :Encoder
end
