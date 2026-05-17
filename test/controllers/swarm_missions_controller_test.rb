require "test_helper"
require_relative "concerns/cross_tenancy_assertions"

class SwarmMissionsControllerTest < ActionDispatch::IntegrationTest
  include CrossTenancyAssertions

  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
    sign_in_as users(:one)
  end

  test "create kicks off decompose_later + redirects to show" do
    assert_enqueued_with(job: Swarm::DecompositionJob) do
      post swarm_missions_path,
           params: { swarm_mission: { title: "M", goal: "Build the X", mode: "auto" } }
    end
    mission = SwarmMission.order(:id).last
    assert_redirected_to swarm_mission_path(mission)
  end

  test "show returns 404 for missions owned by another user" do
    # users(:two) added in Task 6.0 Step 4 specifically for cross-tenancy tests.
    mission = SwarmMission.create!(user: users(:two), created_by: users(:two), title: "X", goal: "Y")
    assert_404_for_cross_tenant_show swarm_mission_path(mission)
  end
end
