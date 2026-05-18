require "test_helper"

class SwarmKanbansControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "show excludes assignments from inactive missions (complete, cancelled, planning_failed)" do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
    profile = AgentProfile.find_by!(slug: "backend")

    active_mission = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "Active", goal: "g", state: :executing)
    active_assignment = SwarmAssignment.create!(swarm_mission: active_mission, agent_profile: profile, task: "Active task", state: :running)

    complete_mission = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "Complete", goal: "g", state: :complete)
    SwarmAssignment.create!(swarm_mission: complete_mission, agent_profile: profile, task: "Complete task", state: :completed)

    cancelled_mission = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "Cancelled", goal: "g", state: :cancelled)
    SwarmAssignment.create!(swarm_mission: cancelled_mission, agent_profile: profile, task: "Cancelled task", state: :cancelled)

    failed_mission = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "Failed", goal: "g", state: :planning_failed)
    SwarmAssignment.create!(swarm_mission: failed_mission, agent_profile: profile, task: "Failed task", state: :pending)

    get swarm_kanban_path
    assert_response :ok
    assert_match "Active task", response.body
    assert_no_match(/Complete task/, response.body)
    assert_no_match(/Cancelled task/, response.body)
    assert_no_match(/Failed task/, response.body)
  end

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
