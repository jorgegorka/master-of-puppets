class ScheduledJob::RunnerJob < ApplicationJob
  queue_as :default

  def perform(scheduled_job)
    scheduled_job.run!
  end
end
