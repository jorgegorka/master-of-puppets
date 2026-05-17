require "test_helper"

class JobRun::SweepStaleJobTest < ActiveJob::TestCase
  test "performs JobRun.sweep_stale!" do
    called = false
    JobRun.stub(:sweep_stale!, ->() { called = true }) do
      JobRun::SweepStaleJob.perform_now
    end
    assert called, "expected JobRun.sweep_stale! to be called"
  end
end
