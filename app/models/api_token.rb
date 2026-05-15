class ApiToken < ApplicationRecord
  include Eventable

  belongs_to :user, default: -> { Current.user }

  has_secure_password :token, validations: false

  validates :name, presence: true
  validates :prefix, presence: true, uniqueness: true

  scope :recent, -> { order(created_at: :desc) }

  def self.create_with_secret!(user:, name:, scopes: [])
    raw_secret = SecureRandom.hex(16)
    prefix     = SecureRandom.alphanumeric(8).downcase
    record     = create!(user: user, name: name, scopes: scopes, prefix: prefix, token: raw_secret)
    [ record, "#{prefix}.#{raw_secret}" ]
  end

  def self.authenticate(presented)
    prefix, secret = presented.to_s.split(".", 2)
    return nil if prefix.blank? || secret.blank?
    record = find_by(prefix: prefix)
    record&.authenticate_token(secret) || nil
  end
end
