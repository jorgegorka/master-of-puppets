require "test_helper"

class Swarm::DecompositionJobTest < ActiveSupport::TestCase
  test "perform delegates to mission.decompose!" do
    Current.user = users(:one)
    mission = swarm_missions(:alpha)
    called = false
    with_singleton_method(mission, :decompose!, -> { called = true }) do
      Swarm::DecompositionJob.new.perform(mission)
    end
    assert called
  end
end
