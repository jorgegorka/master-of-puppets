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

  # A worker's effective tool kit = the profile's declared skills intersected
  # with the skills the given user has actually enabled. Used by the conductor
  # to size up which tools a profile can really wield in a session.
  def skills_for(user)
    skills.merge(Skill.enabled_for(user))
  end
end
