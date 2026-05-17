module Swarm
  class DispatchJob < ApplicationJob
    def perform(mission) = mission.dispatch!
  end
end
