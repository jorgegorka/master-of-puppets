require "test_helper"

class Swarm::OrchestratorLoopJobTest < ActiveSupport::TestCase
  test "perform calls SwarmMission.advance_all_active" do
    called = false
    with_singleton_method(SwarmMission, :advance_all_active, -> { called = true }) do
      Swarm::OrchestratorLoopJob.new.perform
    end
    assert called
  end
end
