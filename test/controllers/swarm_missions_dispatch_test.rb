require "test_helper"

class SwarmMissionsDispatchTest < ActionDispatch::IntegrationTest
  setup do
    Current.user = users(:one)
    sign_in_as users(:one)
    AgentProfile.refresh_from_yaml!
  end

  test "auto-mode mission enqueues DecompositionJob and DispatchJob on create" do
    assert_enqueued_with(job: Swarm::DecompositionJob) do
      assert_enqueued_with(job: Swarm::DispatchJob) do
        post swarm_missions_path,
             params: { swarm_mission: { title: "Auto", goal: "G", mode: "auto" } }
      end
    end
  end

  test "manual-mode mission enqueues decompose but not dispatch" do
    assert_enqueued_with(job: Swarm::DecompositionJob) do
      assert_no_enqueued_jobs only: Swarm::DispatchJob do
        post swarm_missions_path,
             params: { swarm_mission: { title: "Manual", goal: "G", mode: "manual" } }
      end
    end
  end
end
