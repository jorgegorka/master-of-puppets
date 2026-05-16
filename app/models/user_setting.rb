class UserSetting < ApplicationRecord
  THEMES  = %w[
    claude-official claude-official-light
    claude-classic  claude-classic-light
    slate           slate-light
    mono            mono-light
  ].freeze

  ACCENTS = %w[indigo green red yellow violet].freeze

  belongs_to :user

  validates :theme,  presence: true, inclusion: { in: THEMES }
  validates :accent, presence: true, inclusion: { in: ACCENTS }
end
