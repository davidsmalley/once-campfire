require "apns/pool"
require "apns/notification"

Rails.application.configure do
  config.x.apns.auth_key_path = ENV.fetch("APNS_AUTH_KEY_PATH", Rails.application.credentials.dig(:apns, :auth_key_path))
  config.x.apns.key_id = ENV.fetch("APNS_KEY_ID", Rails.application.credentials.dig(:apns, :key_id))
  config.x.apns.team_id = ENV.fetch("APNS_TEAM_ID", Rails.application.credentials.dig(:apns, :team_id))
  config.x.apns.bundle_id = ENV.fetch("APNS_BUNDLE_ID", Rails.application.credentials.dig(:apns, :bundle_id))

  config.x.apns_pool = Apns::Pool.new(
    invalid_subscription_handler: ->(subscription_id) do
      Rails.application.executor.wrap do
        Rails.logger.info "Destroying invalid APNs subscription: #{subscription_id}"
        Push::Subscription.find_by(id: subscription_id)&.destroy
      end
    end
  )

  at_exit { config.x.apns_pool.shutdown }
end
