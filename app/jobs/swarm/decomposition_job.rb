module Swarm
  class DecompositionJob < ApplicationJob
    def perform(mission)
      mission.decompose!
      mission.dispatch! if mission.reload.auto? && mission.dispatching?
    end
  end
end
