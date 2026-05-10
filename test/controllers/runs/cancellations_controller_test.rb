require "test_helper"

module Runs
  class CancellationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as(@user)
      cookies[:project_id] = projects(:acme).id
    end

    test "cancels running run" do
      run = runs(:running_run_for_fix_login_bug)
      post run_cancellation_url(run)
      assert_response :redirect
      assert run.reload.cancelled?
    end

    test "refuses to cancel terminal run" do
      run = runs(:completed_run_for_completed_task)
      post run_cancellation_url(run)
      assert_response :redirect
      assert run.reload.completed?
    end
  end
end
