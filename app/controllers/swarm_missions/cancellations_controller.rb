class SwarmMissions::CancellationsController < ApplicationController
  include SwarmMissionScoped

  def create
    @swarm_mission.cancel(reason: params[:reason], user: Current.user)
    redirect_to swarm_mission_path(@swarm_mission)
  end
end
