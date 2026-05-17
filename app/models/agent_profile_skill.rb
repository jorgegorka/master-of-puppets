class AgentProfileSkill < ApplicationRecord
  belongs_to :agent_profile
  belongs_to :skill

  validates :skill_id, uniqueness: { scope: :agent_profile_id }
end
