module DatabaseConnection
  def self.setup
    DATABASE_CONFIG['port'] ||= $mysql_port
    ActiveRecord::Base.establish_connection(DATABASE_CONFIG)
    ActiveRecord::Base.connection
  rescue
    ActiveRecord::Base.establish_connection(DATABASE_CONFIG.merge('database' => nil))
    ActiveRecord::Base.connection.create_database(DATABASE_CONFIG['database'])
    ActiveRecord::Base.establish_connection(DATABASE_CONFIG)
  end

  def self.drop_tables
    TABLES.keys.each do |table|
      ActiveRecord::Base.connection.drop_table(table) if ActiveRecord::Base.connection.table_exists?(table)
    end
  end

  def self.create_tables
    TABLES.each do |table, fields|
      fields = fields.dup
      options = fields.last.is_a?(Hash) ? fields.pop : {}
      ActiveRecord::Base.connection.create_table(table, options) do |t|
        fields.each do |column_type, *args|
          t.send(column_type, *args)
        end
      end
    end
  end

  TABLES = {
    :polymorphic_records           => [[:string, :owner_type], [:integer, :owner_id], [:timestamps]],
    :deeply_associated_records     => [[:string, :name], [:integer, :associated_record_id], [:timestamps]],
    :associated_records            => [[:string, :name], [:integer, :item_id], [:integer, :item_two_id]],
    :normalized_associated_records => [[:string, :name], [:integer, :item_id], [:timestamps]],
    :not_cached_records            => [[:string, :name], [:integer, :item_id], [:timestamps]],
    :items                         => [[:integer, :item_id], [:string, :title], [:timestamps]],
    :items2                        => [[:integer, :item_id], [:string, :title], [:timestamps]],
    :keyed_records                 => [[:string, :value], :primary_key => "hashed_key"],
  }

  DATABASE_CONFIG = {
    'adapter'  => 'mysql2',
    'database' => 'identity_cache_test',
    'host'     => '127.0.0.1',
    'username' => 'root'
  }
end
