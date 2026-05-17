require "test_helper"

class Conductor::PromptsTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "decomposition renders mission goal + profile list + skill list" do
    mission = swarm_missions(:alpha)
    profiles = AgentProfile.rostered.to_a
    rendered = Conductor::Prompts.decomposition(mission: mission, profiles: profiles, user: users(:one))
    assert_match(/Build the X feature/, rendered)
    assert_match(/Backend Worker/, rendered)
    assert_match(/Frontend Worker/, rendered)
    assert_match(/Return JSON with the following shape/, rendered)
  end

  test "decomposition is safe with zero rostered profiles" do
    assert_nothing_raised { Conductor::Prompts.decomposition(mission: swarm_missions(:alpha), profiles: [], user: users(:one)) }
  end
end
