class AddPlatformAndDeviceTokenToPushSubscriptions < ActiveRecord::Migration[8.2]
  def change
    add_column :push_subscriptions, :platform, :string, default: "web", null: false
    add_column :push_subscriptions, :device_token, :string

    add_index :push_subscriptions, :device_token, unique: true, where: "device_token IS NOT NULL"
    add_index :push_subscriptions, :platform
  end
end
