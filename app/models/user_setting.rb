class UserSetting < ApplicationRecord
  belongs_to :user

  validates :theme, presence: true
  validates :accent, presence: true
end
