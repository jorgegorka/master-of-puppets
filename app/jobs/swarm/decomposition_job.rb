module Swarm
  class DecompositionJob < ApplicationJob
    def perform(mission) = mission.decompose!
  end
end
