require File.expand_path '../externals_watcher', __FILE__
require 'active_support/all'

class ExternalsCollector

  cattr_accessor :ignored_sql
  self.ignored_sql = [/^SHOW (FULL )?TABLES/, /^SHOW (FULL )?FIELDS/, /^SHOW COLUMNS/]

  def handle(type, args)
    case type
    when :mysql_master, :mysql_slave
      type = :mysql
      if ignored_sql?(args[:sql])
        return
      end
    end

    @events << [type, args, caller]
  end

  attr_reader :events
  def start
    @events = []
    @subscribers = ExternalsWatcher.start_instrumentation(self)
    self
  end

  def stop
    ExternalsWatcher.stop_instrumentation(self, @subscribers)
  end

  def initialize
    if block_given?
      begin
        start
        yield(self)
      ensure
        stop
      end
    end
  end

  private

  def ignored_sql?(sql)
    self.class.ignored_sql.any? {|re| re =~ sql}
  end
end

