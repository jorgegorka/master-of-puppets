class SwarmChannel < ApplicationCable::Channel
  def subscribed
    mission = current_user.swarm_missions.find_by(id: params[:swarm_mission_id])
    if mission
      stream_for mission
    else
      Rails.logger.info("[SwarmChannel] reject: user=#{current_user.id} swarm_mission_id=#{params[:swarm_mission_id]}")
      reject
    end
  end
end
