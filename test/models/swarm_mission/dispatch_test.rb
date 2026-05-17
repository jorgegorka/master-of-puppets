require "test_helper"

class SwarmMissionDispatchTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
  end

  test "dispatch! transitions :dispatching → :executing and calls dispatch_ready" do
    mission = swarm_missions(:alpha); mission.update!(state: :dispatching)
    SwarmAssignment.create!(swarm_mission: mission,
                            agent_profile: AgentProfile.find_by!(slug: "backend"),
                            task: "T")
    called_with = nil
    with_singleton_method(SwarmAssignment, :dispatch_ready, ->(mission:) { called_with = mission }) do
      mission.dispatch!
    end
    assert_equal mission, called_with
    assert_predicate mission, :executing?
  end

  test "dispatch! is a no-op outside :dispatching" do
    mission = swarm_missions(:alpha); mission.update!(state: :executing)
    called = false
    with_singleton_method(SwarmAssignment, :dispatch_ready, ->(**) { called = true }) do
      mission.dispatch!
    end
    refute called
  end
end
