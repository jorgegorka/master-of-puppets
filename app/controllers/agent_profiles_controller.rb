class AgentProfilesController < ApplicationController
  before_action :require_admin

  def index
    @profiles = AgentProfile.order(:display_name)
  end

  def show
    @profile = AgentProfile.find(params[:id])
  end

  def new
    @profile = AgentProfile.new
  end

  def edit
    @profile = AgentProfile.find(params[:id])
  end

  def create
    @profile = AgentProfile.new(profile_params)
    if @profile.save
      @profile.track_event :created
      redirect_to agent_profile_path(@profile)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @profile = AgentProfile.find(params[:id])
    if @profile.update(profile_params)
      redirect_to agent_profile_path(@profile)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    AgentProfile.find(params[:id]).destroy
    redirect_to agent_profiles_path
  end

  private
    def profile_params
      params.require(:agent_profile).permit(
        :slug, :display_name, :role, :model, :provider,
        :cwd, :enabled,
        specialties: [], avoid_tasks: [], skill_ids: []
      )
    end

    def require_admin
      head :forbidden unless Current.user&.admin?
    end
end
