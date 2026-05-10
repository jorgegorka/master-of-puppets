require "test_helper"

module Tasks
  class RejectionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @project = projects(:acme)
      sign_in_with_project(@user, @project)
      @task = tasks(:pending_review_task)
    end

    test "rejection with feedback sends task back, records feedback, posts a comment" do
      assert_difference("@task.messages.count", +1) do
        patch task_rejection_url(@task), params: { feedback: "Tighten up the auth check." }
      end

      assert_redirected_to tasks_path
      assert_equal "Task rejected.", flash[:notice]

      @task.reload
      refute_equal columns(:acme_review).id, @task.column_id
      assert_equal "Tighten up the auth check.", @task.reviewer_feedback
      assert_equal "Tighten up the auth check.", @task.messages.last.body
    end

    test "rejection without feedback is refused and column is unchanged" do
      patch task_rejection_url(@task), params: { feedback: "" }

      assert_response :see_other
      assert_match(/feedback/i, flash[:alert].to_s)
      assert_equal columns(:acme_review).id, @task.reload.column_id
    end

    test "rejection records a task_rejected audit event" do
      assert_difference("AuditEvent.where(action: 'task_rejected').count", +1) do
        patch task_rejection_url(@task), params: { feedback: "Try again." }
      end
    end

    test "rejection is refused when task is not pending review" do
      not_in_review = tasks(:write_tests) # backlog
      patch task_rejection_url(not_in_review), params: { feedback: "no" }

      assert_response :see_other
      assert_equal "Task is not pending review.", flash[:alert]
      assert_equal columns(:acme_backlog).id, not_in_review.reload.column_id
    end

    test "rejection 404s for tasks in another project" do
      foreign_task = tasks(:widgets_task)
      patch task_rejection_url(foreign_task), params: { feedback: "no" }
      assert_redirected_to root_path
    end
  end
end
