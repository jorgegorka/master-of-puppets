class SwarmMission::Cancellation < ApplicationRecord
  self.table_name = "swarm_mission_cancellations"

  belongs_to :swarm_mission
  belongs_to :user, default: -> { Current.user }
end
