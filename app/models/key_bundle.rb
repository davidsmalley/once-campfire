class KeyBundle < ApplicationRecord
  belongs_to :user

  validates :identity_key, :signed_pre_key, :signed_pre_key_signature, :signed_pre_key_id, presence: true
end
