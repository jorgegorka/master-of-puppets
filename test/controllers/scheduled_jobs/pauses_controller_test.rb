require "test_helper"

class ScheduledJobs::PausesControllerTest < ActionDispatch::IntegrationTest
  include ControllerSignInHelpers

  test "POST creates pause" do
    sign_in_as users(:one)
    sj = scheduled_jobs(:daily_digest)
    assert_changes -> { sj.reload.paused? }, from: false, to: true do
      post scheduled_job_pause_path(sj)
    end
    assert_redirected_to scheduled_job_path(sj)
  end

  test "DELETE resumes" do
    sign_in_as users(:one)
    sj = scheduled_jobs(:daily_digest)
    sj.pause
    assert_changes -> { sj.reload.paused? }, from: true, to: false do
      delete scheduled_job_pause_path(sj)
    end
  end

  test "cross-tenancy: cannot pause another user's job" do
    sign_in_as users(:member)
    post scheduled_job_pause_path(scheduled_jobs(:daily_digest))
    assert_response :not_found
  end
end
