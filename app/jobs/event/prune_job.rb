class Event::PruneJob < ApplicationJob
  queue_as :default

  def perform
    Event.prune!
  end
end
