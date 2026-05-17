class SwarmKanbansController < ApplicationController
  def show
    @assignments_by_state = Current.user.swarm_missions
                                       .flat_map { |m| m.assignments.includes(:agent_profile) }
                                       .group_by(&:state)
  end
end
