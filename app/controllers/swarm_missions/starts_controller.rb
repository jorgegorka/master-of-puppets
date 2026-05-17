class SwarmMissions::StartsController < ApplicationController
  include SwarmMissionScoped

  def create
    @swarm_mission.dispatch!
    redirect_to swarm_mission_path(@swarm_mission)
  end
end
