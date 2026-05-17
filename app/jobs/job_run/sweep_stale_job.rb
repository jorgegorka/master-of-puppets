class JobRun::SweepStaleJob < ApplicationJob
  queue_as :default

  def perform
    JobRun.sweep_stale!
  end
end
