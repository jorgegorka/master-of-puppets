class SchedulerTickJob < ApplicationJob
  queue_as :default

  # Only one tick may be processing at a time. Prevents clock drift / duplicate
  # recurring enqueues from double-firing ScheduledJob.run_all_due — which
  # would otherwise enqueue two RunnerJobs for the same `next_run_at` snapshot.
  # H7 catches the paused-state race; this catches the queue-level race.
  limits_concurrency to: 1, key: "scheduler_tick", on_conflict: :discard

  def perform
    ScheduledJob.run_all_due
  end
end
