require "test_helper"

class SwarmMissionsModeToggleTest < ActionDispatch::IntegrationTest
  setup do
    Current.user = users(:one)
    sign_in_as users(:one)
    AgentProfile.refresh_from_yaml!
  end

  test "patch mode flips :auto ↔ :manual" do
    m = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "X", goal: "Y", mode: :auto)
    patch swarm_mission_path(m), params: { swarm_mission: { mode: "manual" } }
    assert_equal "manual", m.reload.mode
  end
end
