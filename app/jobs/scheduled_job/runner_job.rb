class ScheduledJob::RunnerJob < ApplicationJob
  queue_as :default

  # Re-check pause state at dispatch time. The scheduler tick enqueues based
  # on a snapshot from `ScheduledJob.run_all_due`; between enqueue and
  # perform, the user can pause the job. Skip rather than run.
  def perform(scheduled_job)
    if scheduled_job.paused?
      Rails.logger.info("[ScheduledJob::RunnerJob] skipping paused job ##{scheduled_job.id} (#{scheduled_job.name})")
      return
    end

    scheduled_job.run!
  end
end
