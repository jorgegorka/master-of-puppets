require "test_helper"

class SchedulerTickJobTest < ActiveJob::TestCase
  test "enqueues RunnerJob for each due, active job" do
    due     = scheduled_jobs(:hourly_lint)   # next_run_at: 5 minutes ago (active)
    not_due = scheduled_jobs(:daily_digest)  # next_run_at: 1 hour from now (active)
    assert not_due.next_run_at > Time.current, "not_due fixture must be in the future"

    assert_enqueued_with(job: ScheduledJob::RunnerJob, args: [ due ]) do
      assert_enqueued_jobs 1, only: ScheduledJob::RunnerJob do
        SchedulerTickJob.perform_now
      end
    end
  end

  test "skips paused jobs" do
    due = scheduled_jobs(:hourly_lint)
    due.pause(reason: "test")

    assert_no_enqueued_jobs only: ScheduledJob::RunnerJob do
      SchedulerTickJob.perform_now
    end
  end

  test "limits_concurrency is configured with key 'scheduler_tick' and on_conflict :discard" do
    assert_equal "scheduler_tick", SchedulerTickJob.concurrency_key
    assert_equal 1,                SchedulerTickJob.concurrency_limit
    assert_equal :discard,         SchedulerTickJob.concurrency_on_conflict
  end
end
