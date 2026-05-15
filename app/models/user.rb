class User < ApplicationRecord
  include Eventable

  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, member: 0, admin: 1

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  normalizes :email, with: -> { _1.to_s.downcase.strip }
end
