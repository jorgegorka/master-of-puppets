require "test_helper"

class JobRunSweepStaleTest < ActiveSupport::TestCase
  STALE_AFTER = 1.hour

  test "sweep_stale! flips :running rows older than threshold to :failed" do
    stuck = job_runs(:succeeded_one).dup
    stuck.assign_attributes(status: :running, started_at: 2.hours.ago, finished_at: nil, output: nil, prompt_tokens: nil, completion_tokens: nil, cost_usd: nil, error_message: nil)
    stuck.save!(validate: false)

    JobRun.sweep_stale!

    stuck.reload
    assert stuck.failed?, "expected stale running row to flip to failed, was #{stuck.status}"
    assert_match(/stale/i, stuck.error_message)
    assert_not_nil stuck.finished_at
  end

  test "sweep_stale! leaves fresh :running rows alone" do
    fresh = job_runs(:succeeded_one).dup
    fresh.assign_attributes(status: :running, started_at: 5.minutes.ago, finished_at: nil)
    fresh.save!(validate: false)

    assert_no_changes -> { fresh.reload.status } do
      JobRun.sweep_stale!
    end
  end

  test "sweep_stale! ignores rows already in a terminal state" do
    done = job_runs(:succeeded_one)
    assert done.succeeded?
    assert_no_changes -> { done.reload.status } do
      JobRun.sweep_stale!
    end
  end
end
