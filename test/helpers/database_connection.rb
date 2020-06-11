# frozen_string_literal: true
module DatabaseConnection
  def self.db_name
    ENV.fetch('DB', 'mysql2')
  end

  def self.setup
    db_config = ENV['DATABASE_URL'] || DEFAULT_CONFIG[db_name]
    begin
      ActiveRecord::Base.establish_connection(db_config)
      ActiveRecord::Base.connection
    rescue
      raise unless db_config.is_a?(Hash)
      ActiveRecord::Base.establish_connection(db_config.merge('database' => nil))
      ActiveRecord::Base.connection.create_database(db_config['database'])
      ActiveRecord::Base.establish_connection(db_config)
    end
  end

  def self.drop_tables
    TABLES.keys.each do |table|
      ActiveRecord::Base.connection.drop_table(table) if table_exists?(table)
    end
  end

  def self.table_exists?(table)
    if ActiveRecord::Base.connection.respond_to?(:data_source_exists?)
      ActiveRecord::Base.connection.data_source_exists?(table)
    else
      ActiveRecord::Base.connection.table_exists?(table)
    end
  end

  def self.create_tables
    TABLES.each do |table, fields|
      fields = fields.dup
      options = fields.last.is_a?(Hash) ? fields.pop : {}
      ActiveRecord::Base.connection.create_table(table, **options) do |t|
        fields.each do |column_type, *args|
          if args.last.is_a?(Hash)
            kwargs = args.pop
            t.send(column_type, *args, **kwargs)
          else
            t.send(column_type, *args)
          end
        end
      end
    end
  end

  TABLES = {
    polymorphic_records: [[:string, :owner_type], [:integer, :owner_id], [:timestamps, null: true]],
    deeply_associated_records: [
      [:string, :name], [:integer, :associated_record_id], [:integer, :item_id], [:timestamps, null: true]
    ],
    associated_records: [[:string, :name], [:integer, :item_id], [:integer, :item_two_id], [:timestamps, null: true]],
    normalized_associated_records: [[:string, :name], [:integer, :item_id], [:timestamps, null: true]],
    no_inverse_of_records: [[:integer, :owner_id], [:timestamps, null: true]],
    not_cached_records: [[:string, :name], [:integer, :item_id], [:timestamps, null: true]],
    items: [[:integer, :item_id], [:string, :title], [:timestamps, null: true]],
    items2: [[:integer, :item_id], [:string, :title], [:timestamps, null: true]],
    related_items: [[:integer, :owner_id], [:string, :owner_type], [:integer, :item_id], [:timestamps, null: true]],
    keyed_records: [[:string, :value], primary_key: "hashed_key"],
    sti_records: [[:string, :type], [:string, :name]],
    custom_master_records: [[:integer, :master_primary_key], id: false, primary_key: 'master_primary_key'],
    custom_child_records: [
      [:integer, :child_primary_key], [:integer, :master_id], id: false, primary_key: 'child_primary_key'
    ],
  }

  DEFAULT_CONFIG = {
    'mysql2' => {
      'adapter' => 'mysql2',
      'database' => 'identity_cache_test',
      'host' => ENV['MYSQL_HOST'] || '127.0.0.1',
      'username' => 'root',
    },
    'postgresql' => {
      'adapter' => 'postgresql',
      'database' => 'identity_cache_test',
      'host' => ENV['POSTGRES_HOST'] || '127.0.0.1',
      'username' => 'postgres',
      'prepared_statements' => false,
    },
  }
end
