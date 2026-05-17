require "test_helper"

class ScheduledJob::RunnerJobTest < ActiveJob::TestCase
  test "perform skips the run when the scheduled_job is paused" do
    sj = scheduled_jobs(:daily_digest)
    sj.pause(reason: "test")

    assert_no_difference -> { JobRun.count } do
      ScheduledJob::RunnerJob.perform_now(sj)
    end
  end

  test "perform runs the scheduled_job when not paused" do
    sj = scheduled_jobs(:daily_digest)
    assert sj.active?

    # Stub the LLM so #run_now completes without HTTP.
    adapter = LlmStubs::StubAdapter.new(text: "ok")
    with_stubbed_llm(adapter) do
      assert_difference -> { JobRun.count }, +1 do
        ScheduledJob::RunnerJob.perform_now(sj)
      end
    end
  end
end
