class ExternalsWatcher

  SUBSCRIPTIONS = ["sql.active_record", "query.memcached"]

  @@receivers = []

  def self.instrument(receiver, &block)
    subscribers = start_instrumentation(receiver)
    yield
  ensure
    stop_instrumentation(receiver, subscribers)
  end

  def self.start_instrumentation(receiver)
    @@receivers.none? and subscribers = register_asn_subscriptions
    @@receivers << receiver
    subscribers
  end

  def self.stop_instrumentation(receiver, subscribers)
    @@receivers -= [receiver]
    subscribers and unregister_asn_subscriptions(subscribers)
  end

  def self.paused?
    defined?(@@paused) && @@paused
  end

  def self.paused
    old_paused = paused?
    @@paused = true
    yield
  ensure
    @@paused = old_paused
  end

  def self.handle(type, ts1, ts2, digest, args)
    return if paused?

    transformed_type = transform_type(type)
    @@receivers.each do |r|
      r.handle(transformed_type, args)
    end
  end

  private

  def self.transform_type(type)
    case type
    when "query.memcached" ; :memcached
    when "sql.active_record"
      return :mysql_master unless ActiveRecord::Base.respond_to?(:connection_proxy)
      conn = ActiveRecord::Base.connection_proxy.connection_stack.current
      conn == ActiveRecord::Base ? :mysql_master : :mysql_slave
    end
  end

  def self.register_asn_subscriptions
    SUBSCRIPTIONS.map do |s|
      ActiveSupport::Notifications.subscribe(s, &method(:handle))
    end
  end

  def self.unregister_asn_subscriptions(subscribers)
    subscribers.map do |s|
      ActiveSupport::Notifications.unsubscribe(s)
    end
  end
end