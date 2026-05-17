class SwarmMissions::AssignmentsController < ApplicationController
  include SwarmMissionScoped

  def update
    asg = @swarm_mission.assignments.find(params[:id])
    apply_state_transition(asg, params[:state])
    if params[:operator_input].present?
      asg.unblock!(operator_input: params[:operator_input])
    elsif params.key?(:review_required)
      asg.update!(review_required: params[:review_required] == "true")
    end
    redirect_to swarm_mission_path(@swarm_mission), status: :see_other
  end

  private
    # Manual transitions wired from the kanban board (Task 6.16). The model
    # methods guard their own preconditions, so we just dispatch by name.
    def apply_state_transition(asg, requested_state)
      case requested_state
      when "dispatched" then asg.dispatch! if asg.pending?
      when "cancelled"  then asg.cancel!
      end
    end
end
