require "test_helper"

class SwarmMission::CancellableTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "cancel! creates child row + flips state + tracks event" do
    mission = swarm_missions(:alpha)
    assert_not mission.cancelled?
    assert_difference -> { Event.where(action: "swarm_mission_cancelled").count }, 1 do
      mission.cancel(reason: "demo", user: users(:one))
    end
    assert_predicate mission, :cancelled?
    assert_equal "demo", mission.cancel_record.reason
    assert_equal users(:one), mission.cancel_record.user
  end

  test "cancel! is idempotent" do
    mission = swarm_missions(:alpha)
    mission.cancel(reason: "first")
    assert_no_difference -> { SwarmMission::Cancellation.count } do
      mission.cancel(reason: "second")
    end
  end

  test "cancel! propagates to live assignments → :cancelled" do
    mission = swarm_missions(:alpha)
    a = SwarmAssignment.create!(swarm_mission: mission, agent_profile: agent_profiles(:backend),
                                task: "Do", state: :running)
    mission.cancel
    assert_equal "cancelled", a.reload.state
  end
end
