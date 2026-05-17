require "test_helper"

class SwarmChannelTest < ActionCable::Channel::TestCase
  setup { Current.user = users(:one) }

  test "subscribes to the mission stream when the user owns it" do
    mission = swarm_missions(:alpha)
    stub_connection current_user: users(:one)
    subscribe(swarm_mission_id: mission.id)
    assert subscription.confirmed?
    assert_has_stream_for mission
  end

  test "rejects subscription when the user does not own the mission" do
    mission = swarm_missions(:alpha) # belongs to users(:one)
    stub_connection current_user: users(:two)
    subscribe(swarm_mission_id: mission.id)
    assert subscription.rejected?
  end
end
