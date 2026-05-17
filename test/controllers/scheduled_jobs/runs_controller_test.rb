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

  test "GET show of a failed run with empty output renders the error block, not an empty <pre>" do
    sign_in_as users(:one)
    run = job_runs(:succeeded_one)
    run.update!(status: :failed, output: "", error_message: "provider 500")

    get scheduled_job_run_path(run.scheduled_job, run)
    assert_response :success

    # Error block is rendered
    assert_match(/provider 500/, response.body)
    # The Output heading should still appear, but the <pre> should be the
    # "no output captured" fallback, not an empty element.
    assert_match(/no output captured/i, response.body)
    assert_no_match(/<pre>\s*<\/pre>/, response.body)
  end

  test "GET show of a succeeded run with non-empty output renders the <pre> normally" do
    sign_in_as users(:one)
    run = job_runs(:succeeded_one)
    assert_equal "Done.", run.output  # fixture
    get scheduled_job_run_path(run.scheduled_job, run)
    assert_response :success
    assert_match(/<pre[^>]*>Done\.<\/pre>/, response.body)
  end
end
