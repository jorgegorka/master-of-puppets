class User < ApplicationRecord
  include Eventable

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one  :user_setting, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :chat_sessions, dependent: :destroy

  enum :role, member: 0, admin: 1

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  normalizes :email, with: -> { _1.to_s.downcase.strip }

  after_create :create_default_settings

  private
    def create_default_settings
      create_user_setting! unless user_setting
    end
end
