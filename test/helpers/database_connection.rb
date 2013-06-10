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
      ActiveRecord::Base.connection.create_table(table) do |t|
        fields.each do |column_type, *args|
          t.send(column_type, *args)
        end
      end
    end
  end

  TABLES = {
    :polymorphic_records        => [[:string, :owner_type], [:integer, :owner_id], [:timestamps]],
    :deeply_associated_records  => [[:string, :name], [:integer, :associated_record_id]],
    :associated_records         => [[:string, :name], [:integer, :record_id]],
    :not_cached_records         => [[:string, :name], [:integer, :record_id]],
    :records                    => [[:integer, :record_id], [:string, :title], [:timestamps]],
    :records2                   => [[:integer, :record_id], [:string, :title], [:timestamps]]
  }

  DATABASE_CONFIG = {
    'adapter'  => 'mysql2',
    'database' => 'identity_cache_test',
    'host'     => '127.0.0.1',
    'username' => 'root'
  }
end
