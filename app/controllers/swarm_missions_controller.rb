class SwarmMissionsController < ApplicationController
  include SwarmMissionScoped
  skip_before_action :set_swarm_mission, only: %i[index new create]

  def index
    @missions = Current.user.swarm_missions.recent
  end

  def show
    @assignments = @swarm_mission.assignments.includes(:agent_profile, :checkpoints)
    @feed        = @swarm_mission.swarm_events.recent.limit(100)
  end

  def new
    @swarm_mission = SwarmMission.new(mode: :auto)
  end

  def create
    @swarm_mission = SwarmMission.new(swarm_mission_params.merge(user: Current.user, created_by: Current.user))
    if @swarm_mission.save
      @swarm_mission.track_event :created
      @swarm_mission.decompose_later
      @swarm_mission.dispatch_later if @swarm_mission.auto?
      redirect_to swarm_mission_path(@swarm_mission)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @swarm_mission.update(swarm_mission_params)
      redirect_to swarm_mission_path(@swarm_mission)
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @swarm_mission.destroy
    redirect_to swarm_missions_path
  end

  private
    def swarm_mission_params
      params.require(:swarm_mission).permit(:title, :goal, :mode)
    end
end
