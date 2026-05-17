class AgentProfile < ApplicationRecord
  include Eventable
  include Loadable

  has_many :agent_profile_skills, dependent: :destroy
  has_many :skills, through: :agent_profile_skills

  enum :status, { online: 0, away: 1, offline: 2 }

  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9][a-z0-9_-]{0,63}\z/ }
  validates :display_name, :role, :model, :provider, :cwd, presence: true

  scope :enabled,  -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :rostered, -> { enabled.order(:display_name) }
end
