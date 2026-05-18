class SwarmKanbansController < ApplicationController
  def show
    @assignments_by_state = SwarmAssignment
      .joins(:swarm_mission)
      .merge(SwarmMission.active.for_user(Current.user))
      .includes(:agent_profile, :swarm_mission)
      .group_by(&:state)
  end
end
