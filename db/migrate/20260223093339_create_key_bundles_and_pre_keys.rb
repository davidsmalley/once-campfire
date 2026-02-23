class CreateKeyBundlesAndPreKeys < ActiveRecord::Migration[8.2]
  def change
    create_table :key_bundles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.binary :identity_key, null: false
      t.binary :signed_pre_key, null: false
      t.binary :signed_pre_key_signature, null: false
      t.integer :signed_pre_key_id, null: false
      t.timestamps
    end

    create_table :pre_keys do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.integer :key_id, null: false
      t.binary :public_key, null: false
      t.timestamps
    end

    add_index :pre_keys, [:user_id, :key_id], unique: true
  end
end
