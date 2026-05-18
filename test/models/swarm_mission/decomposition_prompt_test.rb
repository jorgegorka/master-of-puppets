require "test_helper"

class SwarmMission::DecompositionPromptTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "renders mission goal + profile list + skill list" do
    mission  = swarm_missions(:alpha)
    profiles = AgentProfile.rostered.to_a
    rendered = mission.decomposition_prompt(profiles: profiles, user: users(:one)).to_s

    assert_match(/Build the X feature/, rendered)
    assert_match(/Backend Worker/, rendered)
    assert_match(/Frontend Worker/, rendered)
    assert_match(/Return JSON with the following shape/, rendered)
  end

  test "is safe with zero rostered profiles" do
    assert_nothing_raised do
      swarm_missions(:alpha).decomposition_prompt(profiles: [], user: users(:one)).to_s
    end
  end
end
