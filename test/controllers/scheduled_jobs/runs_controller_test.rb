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

  test "GET show renders truncated-output banner when output_truncated_at_bytes is set" do
    sign_in_as users(:one)
    run = job_runs(:succeeded_one)
    run.update!(output_truncated_at_bytes: 500_000)
    get scheduled_job_run_path(run.scheduled_job, run)
    assert_response :success
    assert_match(/truncated/i, response.body)
  end

  test "GET show does not render banner when output is not truncated" do
    sign_in_as users(:one)
    run = job_runs(:succeeded_one)
    assert_nil run.output_truncated_at_bytes
    get scheduled_job_run_path(run.scheduled_job, run)
    assert_response :success
    assert_no_match(/truncated at \d+ bytes/i, response.body)
  end

  test "cross-tenancy: 404 on other user's run" do
    sign_in_as users(:member)
    get scheduled_job_runs_path(scheduled_jobs(:daily_digest))
    assert_response :not_found
  end

  test "cross-tenancy: POST create does not enqueue and returns 404" do
    sign_in_as users(:member)
    assert_no_enqueued_jobs only: ScheduledJob::RunnerJob do
      post scheduled_job_runs_path(scheduled_jobs(:daily_digest))
    end
    assert_response :not_found
  end

  test "cross-tenancy: GET show of other user's run returns 404" do
    sign_in_as users(:member)
    get scheduled_job_run_path(scheduled_jobs(:daily_digest), job_runs(:succeeded_one))
    assert_response :not_found
  end
end
