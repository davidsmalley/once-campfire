class PreKey < ApplicationRecord
  belongs_to :user

  validates :key_id, presence: true, uniqueness: { scope: :user_id }
  validates :public_key, presence: true
end
