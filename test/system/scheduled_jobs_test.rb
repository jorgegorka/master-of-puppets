require "application_system_test_case"

class ScheduledJobsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "user creates a job, runs it manually, sees the run on the dashboard" do
    # Stub the LLM adapter so the run completes deterministically.
    # restore_llm_adapter is called automatically by ApplicationSystemTestCase
    # teardown.
    stub_llm_adapter_with_completion("Run output text.")

    sign_in(users(:one))
    visit scheduled_jobs_path
    click_on "New job"

    fill_in "Name",   with: "Daily summary"
    fill_in "Cron",   with: "0 9 * * *"
    fill_in "Prompt", with: "Hi"
    click_on "Create"

    assert_text "Job scheduled."

    # Drain the queue around the "Run now" click so RunnerJob#perform runs
    # synchronously and the JobRun reaches :succeeded before we assert.
    perform_enqueued_jobs do
      click_on "Run now"
      assert_text "Run queued."
      using_wait_time(5) { assert_text "succeeded" }
    end

    visit root_path  # dashboard
    assert_text "Daily summary"
    assert_text "succeeded"
  end
end
