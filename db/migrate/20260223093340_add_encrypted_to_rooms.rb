class AddEncryptedToRooms < ActiveRecord::Migration[8.2]
  def change
    add_column :rooms, :encrypted, :boolean, default: false, null: false
  end
end
