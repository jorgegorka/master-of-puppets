require "test_helper"

class ReapStalledRunsJobTest < ActiveJob::TestCase
  test "fails runs idle past threshold" do
    run = runs(:running_run_for_fix_login_bug)
    run.update_columns(last_activity_at: 10.minutes.ago)

    ReapStalledRunsJob.perform_now
    assert run.reload.failed?
  end

  test "leaves recent runs alone" do
    run = runs(:running_run_for_fix_login_bug)
    run.update_columns(last_activity_at: 30.seconds.ago)

    ReapStalledRunsJob.perform_now
    assert run.reload.running?
  end
end
