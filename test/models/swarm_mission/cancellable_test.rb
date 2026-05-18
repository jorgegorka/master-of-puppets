require "test_helper"

class SwarmMission::CancellableTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "cancel! creates child row + flips state + tracks event" do
    mission = swarm_missions(:alpha)
    assert_not mission.cancelled?
    assert_difference -> { Event.where(action: "swarm_mission_cancelled").count }, 1 do
      mission.cancel!(reason: "demo", user: users(:one))
    end
    assert_predicate mission, :cancelled?
    assert_equal "demo", mission.cancel_record.reason
    assert_equal users(:one), mission.cancel_record.user
  end

  test "cancel! is idempotent" do
    mission = swarm_missions(:alpha)
    mission.cancel!(reason: "first")
    assert_no_difference -> { SwarmMission::Cancellation.count } do
      mission.cancel!(reason: "second")
    end
  end

  test "cancel! propagates to live assignments → :cancelled" do
    mission = swarm_missions(:alpha)
    a = SwarmAssignment.create!(swarm_mission: mission, agent_profile: agent_profiles(:backend),
                                task: "Do", state: :running)
    mission.cancel!
    assert_equal "cancelled", a.reload.state
  end

  test "cancel! also cancels pending assignments (not just live)" do
    mission = swarm_missions(:alpha)
    pending_asg = SwarmAssignment.create!(swarm_mission: mission, agent_profile: agent_profiles(:backend),
                                          task: "Pending work", state: :pending)
    mission.cancel!(reason: "test")
    assert_equal "cancelled", pending_asg.reload.state
  end

  test "cancel delegates to SwarmAssignment#cancel! so TmuxBridge.close_worker is called for each live assignment" do
    mission = swarm_missions(:alpha)
    _a1 = SwarmAssignment.create!(swarm_mission: mission, agent_profile: agent_profiles(:backend),
                                  task: "Task 1", state: :running)
    _a2 = SwarmAssignment.create!(swarm_mission: mission, agent_profile: agent_profiles(:backend),
                                  task: "Task 2", state: :dispatched)

    closed_ids = []
    Swarm::TmuxBridge.stub(:close_worker, ->(asg) { closed_ids << asg.id }) do
      mission.cancel!(reason: "test")
    end

    assert_equal 2, closed_ids.size, "TmuxBridge.close_worker should be called for every live assignment"
  end
end
