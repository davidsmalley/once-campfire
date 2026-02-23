require "net/http"
require "uri"
require "restricted_http/private_network_guard"

class Webhook < ApplicationRecord
  ENDPOINT_TIMEOUT = 7.seconds
  MAX_RESPONSE_BODY_SIZE = 5.megabytes

  ALLOWED_ATTACHMENT_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp
    application/pdf
  ].freeze

  belongs_to :user

  validates :url, presence: true
  validate :url_must_not_target_private_network, if: -> { url.present? }

  def deliver(message)
    post(payload(message)).tap do |response|
      if text = extract_text_from(response)
        receive_text_reply_to(message.room, text: text)
      elsif attachment = extract_attachment_from(response)
        receive_attachment_reply_to(message.room, attachment: attachment)
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout
    receive_text_reply_to message.room, text: "Failed to respond within #{ENDPOINT_TIMEOUT} seconds"
  rescue RestrictedHTTP::Violation
    receive_text_reply_to message.room, text: "Webhook URL must not point to a private network address"
  end

  private
    def post(payload)
      resolved_ip = RestrictedHTTP::PrivateNetworkGuard.resolve(uri.host)
      Net::HTTP.start(uri.host, uri.port, ipaddr: resolved_ip, use_ssl: uri.scheme == "https",
                      open_timeout: ENDPOINT_TIMEOUT, read_timeout: ENDPOINT_TIMEOUT) do |http|
        http.request \
          Net::HTTP::Post.new(uri, "Content-Type" => "application/json").tap { |request| request.body = payload }
      end
    end

    def uri
      @uri ||= URI(url)
    end

    def url_must_not_target_private_network
      RestrictedHTTP::PrivateNetworkGuard.resolve(URI(url).host)
    rescue RestrictedHTTP::Violation
      errors.add(:url, "must not point to a private network address")
    rescue URI::InvalidURIError, Resolv::ResolvError
      errors.add(:url, "is not a valid URL")
    end

    def payload(message)
      {
        user:    { id: message.creator.id, name: message.creator.name },
        room:    { id: message.room.id, name: message.room.name, path: room_bot_messages_path(message) },
        message: { id: message.id, body: { html: message.body.body, plain: without_recipient_mentions(message.plain_text_body) }, path: message_path(message) }
      }.to_json
    end

    def message_path(message)
      Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    end

    def room_bot_messages_path(message)
      Rails.application.routes.url_helpers.room_bot_messages_path(message.room, user.bot_key)
    end

    def extract_text_from(response)
      if response.code == "200" && response.content_type.in?(%w[ text/html text/plain ])
        body = String.new(response.body).force_encoding("UTF-8")
        body.bytesize <= MAX_RESPONSE_BODY_SIZE ? body : nil
      end
    end

    def receive_text_reply_to(room, text:)
      room.messages.create!(body: text, creator: user).broadcast_create
    end

    def extract_attachment_from(response)
      return unless response.code == "200"
      return unless response.content_type && response.content_type.in?(ALLOWED_ATTACHMENT_CONTENT_TYPES)
      return unless response.body.bytesize <= MAX_RESPONSE_BODY_SIZE

      if mime_type = Mime::Type.lookup(response.content_type)
        ActiveStorage::Blob.create_and_upload! \
          io: StringIO.new(response.body), filename: "attachment.#{mime_type.symbol}", content_type: mime_type.to_s
      end
    end

    def receive_attachment_reply_to(room, attachment:)
      room.messages.create_with_attachment!(attachment: attachment, creator: user).broadcast_create
    end

    def without_recipient_mentions(body)
      body \
        .gsub(user.attachable_plain_text_representation(nil), "") # Remove mentions of the recipient user
        .gsub(/\A\p{Space}+|\p{Space}+\z/, "") # Remove leading and trailing whitespace uncluding unicode spaces
    end
end
