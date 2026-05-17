require "test_helper"

class SwarmKanbansControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "show only includes the current user's assignments" do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
    mine_mission = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "M1", goal: "g", state: :executing)
    SwarmAssignment.create!(swarm_mission: mine_mission,
                            agent_profile: AgentProfile.find_by!(slug: "backend"),
                            task: "Mine", state: :running)
    Current.user = users(:two)
    theirs_mission = SwarmMission.create!(user: users(:two), created_by: users(:two), title: "M2", goal: "g", state: :executing)
    SwarmAssignment.create!(swarm_mission: theirs_mission,
                            agent_profile: AgentProfile.find_by!(slug: "backend"),
                            task: "Theirs", state: :running)
    Current.user = users(:one)

    get swarm_kanban_path
    assert_response :ok
    assert_match "Mine", response.body
    assert_no_match(/Theirs/, response.body)
  end
end
