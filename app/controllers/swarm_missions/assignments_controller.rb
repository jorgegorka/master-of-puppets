class SwarmMissions::AssignmentsController < ApplicationController
  include SwarmMissionScoped

  def update
    asg = @swarm_mission.assignments.find(params[:id])
    if params[:operator_input].present?
      asg.unblock!(operator_input: params[:operator_input])
    elsif params.key?(:review_required)
      asg.update!(review_required: params[:review_required] == "true")
    end
    redirect_to swarm_mission_path(@swarm_mission)
  end
end
