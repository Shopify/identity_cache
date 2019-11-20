# frozen_string_literal: true

module IdentityCache
  module Cached
    class RecordFetcher < AbstractFetcher
      attr_accessor :model

      def initialize(model)
        @model = model
      end

      private

      # AbstractFetcher method overrides

      def should_use_cache?
        model.should_use_cache?
      end

      def input_key_to_cache_key(id)
        model.rails_cache_key(id)
      end

      def default_value
        nil
      end

      def encode(record)
        Encoder.encode(record)
      end

      def decode(cache_value)
        Encoder.decode(cache_value, model)
      end

      def load_multi_from_db(ids)
        ids = ids.map { |id| model.connection.type_cast(id, id_column) }
        records = model.where(model.primary_key => ids).includes(db_load_includes).to_a
        setup_embedded_associations_on_miss(records)
        records.index_by(&:id)
      end

      def load_from_db(id)
        record = model.includes(db_load_includes).where(model.primary_key => id).take
        setup_embedded_associations_on_miss([record]) if record
        record
      end

      # helper methods

      protected

      def db_load_includes
        model.send(:cache_fetch_includes)
      end

      private

      def id_column
        @id_column ||= model.columns.detect { |c| c.name == model.primary_key }
      end


      def setup_embedded_associations_on_miss(records)
        model.send(:setup_embedded_associations_on_miss, records)
      end
    end
  end
end
