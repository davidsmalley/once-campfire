class Apns::Notification
  def initialize(title:, body:, path:, badge:, device_token:, room_id: nil, message_id: nil)
    @title, @body, @path, @badge = title, body, path, badge
    @device_token = device_token
    @room_id, @message_id = room_id, message_id
  end

  def deliver(connection:)
    apns_notification = Apnotic::Notification.new(@device_token)
    apns_notification.alert = { title: @title, body: @body }
    apns_notification.badge = @badge
    apns_notification.sound = "default"
    apns_notification.topic = Rails.configuration.x.apns.bundle_id
    apns_notification.thread_id = "room-#{@room_id}" if @room_id
    apns_notification.category = "MESSAGE"
    apns_notification.custom_payload = {
      path: @path,
      room_id: @room_id,
      message_id: @message_id
    }.compact

    response = connection.push(apns_notification)
    handle_response(response)
  end

  private
    def handle_response(response)
      return :failed unless response

      case response.status
      when "200"
        :delivered
      when "410", "404"
        :invalid_token
      else
        Rails.logger.warn "APNs delivery failed: #{response.status} #{response.body}"
        :failed
      end
    end
end
