require "test_helper"

class JobRunTest < ActiveSupport::TestCase
  test "enum statuses round-trip" do
    run = job_runs(:succeeded_one)
    assert run.succeeded?
    run.update!(status: :failed)
    assert run.reload.failed?
  end

  test "duration_seconds nil until both timestamps set" do
    run = scheduled_jobs(:daily_digest).runs.create!(status: :pending)
    assert_nil run.duration_seconds

    run.update!(started_at: 1.second.ago, finished_at: Time.current)
    assert_in_delta 1, run.duration_seconds, 0.5
  end

  test "ScheduledJob#runs returns the run" do
    assert_includes scheduled_jobs(:daily_digest).runs, job_runs(:succeeded_one)
  end

  test "recent scope orders newest first" do
    sj = scheduled_jobs(:daily_digest)
    older = sj.runs.create!(status: :succeeded, started_at: 2.days.ago, finished_at: 2.days.ago + 1.second)
    newer = sj.runs.create!(status: :succeeded, started_at: 1.minute.ago, finished_at: Time.current)
    ordered = sj.runs.recent.pluck(:id)
    assert ordered.index(newer.id) < ordered.index(older.id),
           "newer should come before older in recent scope"
  end
end
