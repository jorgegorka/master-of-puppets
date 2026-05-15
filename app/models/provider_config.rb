class ProviderConfig < ApplicationRecord
  include Eventable

  encrypts :api_key

  validates :provider, presence: true, uniqueness: true

  scope :enabled, -> { where(enabled: true) }
end
