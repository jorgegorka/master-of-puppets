require "test_helper"

class ScheduledJobs::RunsControllerTest < ActionDispatch::IntegrationTest
  include ControllerSignInHelpers

  test "GET index lists runs" do
    sign_in_as users(:one)
    get scheduled_job_runs_path(scheduled_jobs(:daily_digest))
    assert_response :success
  end

  test "POST create enqueues RunnerJob" do
    sign_in_as users(:one)
    sj = scheduled_jobs(:daily_digest)
    assert_enqueued_with(job: ScheduledJob::RunnerJob, args: [ sj ]) do
      post scheduled_job_runs_path(sj)
    end
    assert_redirected_to scheduled_job_path(sj)
  end

  test "GET show of own run" do
    sign_in_as users(:one)
    get scheduled_job_run_path(scheduled_jobs(:daily_digest), job_runs(:succeeded_one))
    assert_response :success
  end

  test "cross-tenancy: 404 on other user's run" do
    sign_in_as users(:member)
    get scheduled_job_runs_path(scheduled_jobs(:daily_digest))
    assert_response :not_found
  end
end
