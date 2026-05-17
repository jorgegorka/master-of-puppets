require "test_helper"

class SwarmAssignmentTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "default state is :pending and review_required is false" do
    a = SwarmAssignment.create!(
      swarm_mission: swarm_missions(:alpha),
      agent_profile: agent_profiles(:backend),
      task: "Do the thing"
    )
    assert_equal "pending", a.state
    assert_equal false, a.review_required
    assert_equal [],    a.depends_on
  end

  test "ready scope = pending && depends_on satisfied" do
    mission = swarm_missions(:alpha)
    first = SwarmAssignment.create!(swarm_mission: mission,
                                    agent_profile: agent_profiles(:backend),
                                    task: "T1", state: :completed)
    ready = SwarmAssignment.create!(swarm_mission: mission,
                                    agent_profile: agent_profiles(:frontend),
                                    task: "T2", depends_on: [ first.id ])
    not_ready = SwarmAssignment.create!(swarm_mission: mission,
                                        agent_profile: agent_profiles(:frontend),
                                        task: "T3", depends_on: [ ready.id ])
    result = SwarmAssignment.ready
    assert_includes result, ready
    refute_includes result, not_ready
  end
end
