require "test_helper"

class SwarmMission::DecomposableTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
  end

  test "decompose! parses JSON envelope, creates assignments, flips state" do
    mission = swarm_missions(:alpha)
    assert_predicate mission, :planning?

    LlmStubs.with_decomposition({
      decomposition_notes: "Plan",
      assignments: [
        { agent_slug: "backend",  task: "T1", rationale: "R1", depends_on: [],     review_required: false },
        { agent_slug: "frontend", task: "T2", rationale: "R2", depends_on: [ 1 ],  review_required: true  }
      ]
    }) do
      assert_difference -> { SwarmAssignment.count }, 2 do
        mission.decompose!
      end
    end

    assert_predicate mission.reload, :dispatching?
    assert_equal "Plan", mission.decomposition_notes
    first, second = mission.assignments.order(:id).to_a
    assert_equal "backend",  first.agent_profile.slug
    assert_equal "frontend", second.agent_profile.slug
    assert_equal [ first.id ], second.depends_on
  end

  test "decompose! on bad JSON transitions to :planning_failed and records failure event" do
    mission = swarm_missions(:alpha)
    LlmStubs.with_decomposition("not json at all") do
      assert_difference -> { mission.events.where(action: "swarm_mission_decomposition_failed").count }, 1 do
        assert_no_difference -> { SwarmAssignment.count } do
          mission.decompose!
        end
      end
    end
    assert_predicate mission.reload, :planning_failed?
  end

  test "decompose! rejects unknown agent_slug with a clear error event" do
    mission = swarm_missions(:alpha)
    LlmStubs.with_decomposition({
      decomposition_notes: "Plan",
      assignments: [
        { agent_slug: "nonexistent", task: "T1", rationale: "R", depends_on: [], review_required: false }
      ]
    }) do
      mission.decompose!
    end
    assert_predicate mission.reload, :planning_failed?
    ev = mission.events.where(action: "swarm_mission_decomposition_failed").last
    assert_match(/unknown agent_slug.*nonexistent/, ev.particulars["error"])
  end

  test "decompose! rejects depends_on cycles" do
    # 1 depends on 2; 2 depends on 1
    mission = swarm_missions(:alpha)
    LlmStubs.with_decomposition({
      decomposition_notes: "Bad plan",
      assignments: [
        { agent_slug: "backend",  task: "T1", rationale: "R", depends_on: [ 2 ], review_required: false },
        { agent_slug: "frontend", task: "T2", rationale: "R", depends_on: [ 1 ], review_required: false }
      ]
    }) do
      mission.decompose!
    end
    assert_predicate mission.reload, :planning_failed?
  end
end
