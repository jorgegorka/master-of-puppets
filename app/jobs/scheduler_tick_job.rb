class SchedulerTickJob < ApplicationJob
  queue_as :default

  def perform
    ScheduledJob.run_all_due
  end
end
