module SwarmMissionScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_swarm_mission
  end

  private
    def set_swarm_mission
      @swarm_mission = Current.user.swarm_missions.find(params[:swarm_mission_id] || params[:id])
    end
end
