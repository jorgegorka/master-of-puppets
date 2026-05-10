require "test_helper"

module Tasks
  class ApprovalsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @project = projects(:acme)
      sign_in_with_project(@user, @project)
      @task = tasks(:pending_review_task)
    end

    test "approves a pending-review task and advances it to the next non-terminal column" do
      patch task_approval_url(@task)

      assert_redirected_to tasks_path
      assert_equal "Task approved.", flash[:notice]

      @task.reload
      refute_equal columns(:acme_review).id, @task.column_id
      assert_not_nil @task.reviewed_at
      assert_equal @user.id, @task.reviewed_by_user_id
    end

    test "approval audit event is recorded" do
      assert_difference("AuditEvent.where(action: 'task_advanced').count", +1) do
        patch task_approval_url(@task)
      end
    end

    test "approval is refused when task is not pending review" do
      not_in_review = tasks(:write_tests) # in acme_backlog
      patch task_approval_url(not_in_review)

      assert_response :see_other
      assert_equal "Task is not pending review.", flash[:alert]
      assert_equal columns(:acme_backlog).id, not_in_review.reload.column_id
    end

    test "approval 404s for tasks in another project" do
      foreign_task = tasks(:widgets_task)
      patch task_approval_url(foreign_task)
      assert_redirected_to root_path
    end
  end
end
