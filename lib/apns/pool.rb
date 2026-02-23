module Apns; end

# Manages APNs HTTP/2 connection and async delivery, mirroring WebPush::Pool
class Apns::Pool
  attr_reader :delivery_pool, :invalidation_pool, :invalid_subscription_handler

  def initialize(invalid_subscription_handler:)
    @delivery_pool = Concurrent::ThreadPoolExecutor.new(max_threads: 10, queue_size: 10000)
    @invalidation_pool = Concurrent::FixedThreadPool.new(1)
    @invalid_subscription_handler = invalid_subscription_handler
    @connection = nil
    @connection_mutex = Mutex.new
  end

  def queue(payload, subscriptions)
    subscriptions.find_each do |subscription|
      deliver_later(payload, subscription)
    end
  end

  def shutdown
    shutdown_pool(delivery_pool)
    shutdown_pool(invalidation_pool)
    @connection_mutex.synchronize do
      @connection&.close
      @connection = nil
    end
  end

  private
    def connection
      @connection_mutex.synchronize do
        @connection = nil if @connection && !connection_alive?(@connection)
        @connection ||= build_connection
      end
    end

    def connection_alive?(conn)
      conn.instance_variable_get(:@stream_id)&.positive?
    rescue
      false
    end

    def build_connection
      if Rails.configuration.x.apns.auth_key_path.present?
        Apnotic::Connection.new(
          auth_method: :token,
          cert_path: Rails.configuration.x.apns.auth_key_path,
          key_id: Rails.configuration.x.apns.key_id,
          team_id: Rails.configuration.x.apns.team_id
        )
      end
    end

    def deliver_later(payload, subscription)
      notification = subscription.notification(**payload)
      subscription_id = subscription.id

      delivery_pool.post do
        deliver(notification, subscription_id)
      rescue Exception => e
        Rails.logger.error "Error in Apns::Pool.deliver: #{e.class} #{e.message}"
      end
    rescue Concurrent::RejectedExecutionError
    end

    def deliver(notification, id)
      conn = connection
      return unless conn

      result = notification.deliver(connection: conn)
      invalidate_subscription_later(id) if result == :invalid_token
    end

    def invalidate_subscription_later(id)
      invalidation_pool.post do
        invalid_subscription_handler.call(id)
      rescue Exception => e
        Rails.logger.error "Error in Apns::Pool.invalid_subscription_handler: #{e.class} #{e.message}"
      end
    end

    def shutdown_pool(pool)
      pool.shutdown
      pool.kill unless pool.wait_for_termination(1)
    end
end
