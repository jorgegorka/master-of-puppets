require "test_helper"

class SwarmEventTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "log! creates a row with occurred_at + sets defaults" do
    mission = swarm_missions(:alpha)
    ev = SwarmEvent.log!(mission: mission, kind: "decomposed", message: "5 assignments planned",
                         data: { assignment_count: 5 })
    assert_equal mission, ev.swarm_mission
    assert_in_delta Time.current.to_f, ev.occurred_at.to_f, 1.0
    assert_equal 5, ev.data["assignment_count"]
  end

  test ".recent orders by occurred_at descending" do
    mission = swarm_missions(:alpha)
    a = SwarmEvent.log!(mission: mission, kind: "k1", message: "first",  data: {}, occurred_at: 5.minutes.ago)
    b = SwarmEvent.log!(mission: mission, kind: "k2", message: "second", data: {})
    assert_equal [ b, a ], mission.swarm_events.recent.to_a.first(2)
  end
end
