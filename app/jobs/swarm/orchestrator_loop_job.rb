module Swarm
  class OrchestratorLoopJob < ApplicationJob
    limits_concurrency to: 1, key: "swarm_orchestrator", on_conflict: :discard

    def perform = SwarmMission.advance_all_active
  end
end
