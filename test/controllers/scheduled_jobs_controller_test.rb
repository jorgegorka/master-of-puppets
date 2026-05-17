require "test_helper"

class ScheduledJobsControllerTest < ActionDispatch::IntegrationTest
  include ControllerSignInHelpers

  test "GET /jobs as authed user lists own jobs" do
    sign_in_as users(:one)
    get scheduled_jobs_path
    assert_response :success
    assert_select "h1", "Jobs"
  end

  test "POST /jobs creates and redirects" do
    sign_in_as users(:one)
    assert_difference -> { ScheduledJob.count }, +1 do
      post scheduled_jobs_path, params: {
        scheduled_job: { name: "Nightly", cron: "0 3 * * *", prompt: "x",
                         model: "claude-haiku-4-5", provider: "anthropic" }
      }
    end
    assert_redirected_to scheduled_job_path(ScheduledJob.last)
  end

  test "GET /jobs/:id of another user returns 404 (cross-tenancy)" do
    sign_in_as users(:member)
    get scheduled_job_path(scheduled_jobs(:daily_digest))
    assert_response :not_found
  end

  test "DELETE /jobs/:id of own job destroys it" do
    sign_in_as users(:one)
    sj = scheduled_jobs(:daily_digest)
    assert_difference -> { ScheduledJob.count }, -1 do
      delete scheduled_job_path(sj)
    end
    assert_redirected_to scheduled_jobs_path
  end

  test "GET /jobs/cron_preview returns next fire time" do
    sign_in_as users(:one)
    get cron_preview_scheduled_jobs_path, params: { cron: "0 9 * * *" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_match(/\d{4}-\d{2}-\d{2}/, json["next_run_at"])
  end

  test "GET /jobs/cron_preview returns 422 on garbage" do
    sign_in_as users(:one)
    get cron_preview_scheduled_jobs_path, params: { cron: "wut" }
    assert_response :unprocessable_content
  end
end
