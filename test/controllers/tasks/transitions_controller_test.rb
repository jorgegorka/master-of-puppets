require "test_helper"

module Tasks
  class TransitionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as(@user)
      cookies[:project_id] = projects(:acme).id
    end

    test "user moves task from manual column" do
      task = tasks(:write_tests)  # in acme_backlog (manual)
      target = columns(:acme_in_progress)
      post task_transition_url(task), params: { target_column_id: target.id, reason: "ready to work" }
      follow_redirect!
      assert_response :success
      assert_equal target.id, task.reload.column_id
    end

    test "user blocked from moving task from agent column" do
      task = tasks(:design_homepage)  # in acme_in_progress (agent)
      target = columns(:acme_review)
      post task_transition_url(task), params: { target_column_id: target.id }
      follow_redirect!
      assert_response :success
      assert_not_equal target.id, task.reload.column_id
    end
  end
end
