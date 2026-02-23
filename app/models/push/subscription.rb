class Push::Subscription < ApplicationRecord
  belongs_to :user

  scope :web, -> { where(platform: "web") }
  scope :ios, -> { where(platform: "ios") }

  validates :platform, inclusion: { in: %w[web ios] }
  validates :device_token, presence: true, uniqueness: true, if: -> { platform == "ios" }
  validates :endpoint, presence: true, if: -> { platform == "web" }

  def notification(**params)
    case platform
    when "web"
      web_params = params.slice(:title, :body, :path)
      WebPush::Notification.new(**web_params, badge: unread_badge_count, endpoint: endpoint, p256dh_key: p256dh_key, auth_key: auth_key)
    when "ios"
      Apns::Notification.new(**params, badge: unread_badge_count, device_token: device_token)
    end
  end

  def web?
    platform == "web"
  end

  def ios?
    platform == "ios"
  end

  private
    def unread_badge_count
      user.memberships.unread.count
    end
end
