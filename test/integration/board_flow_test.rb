require "test_helper"

class BoardFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @project = projects(:acme)
    sign_in_with_project(@user, @project)

    @backlog     = columns(:acme_backlog)
    @in_progress = columns(:acme_in_progress)
    @review      = columns(:acme_review)
    @done        = columns(:acme_done)

    @task = @project.tasks.create!(
      title: "Pipeline test",
      creator: @user,
      column: @backlog,
      entered_column_at: 1.minute.ago,
      position: 999
    )
  end

  test "task flows backlog → in_progress → review → done via the right actors" do
    assert_enqueued_with(job: TriggerColumnJob, args: [ @task.id ]) do
      post task_transition_url(@task), params: { target_column_id: @in_progress.id }
    end
    assert_redirected_to tasks_path
    assert_equal @in_progress.id, @task.reload.column_id
    assert_includes @project.tasks.active, @task

    run = @in_progress.runs.create!(project: @project, task: @task, status: :running, trigger_type: "task_entered")
    Columns::Transition.new(task: @task, actor: run, kind: :advance).call!
    assert_equal @review.id, @task.reload.column_id
    assert @task.pending_review?

    patch task_approval_url(@task)
    assert_redirected_to tasks_path
    assert_equal @done.id, @task.reload.column_id
    assert @task.completed?
    assert @task.terminal?
    assert_not_nil @task.completed_at
    assert_not_nil @task.reviewed_at
    assert_equal @user.id, @task.reviewed_by_user_id
  end

  test "rejected task in review goes back to the previous non-terminal column with feedback recorded" do
    @task.update!(column: @review, entered_column_at: 1.minute.ago, position: 999)

    assert_difference("@task.messages.count", +1) do
      patch task_rejection_url(@task), params: { feedback: "Please fix the auth check first." }
    end
    assert_redirected_to tasks_path

    @task.reload
    assert_equal "Please fix the auth check first.", @task.reviewer_feedback
    assert_includes @task.messages.last.body, "Please fix"
    assert_equal @in_progress.id, @task.column_id
  end

  test "rejection without feedback is refused without changing the column" do
    @task.update!(column: @review, entered_column_at: 1.minute.ago, position: 999)

    patch task_rejection_url(@task), params: { feedback: "" }
    assert_response :see_other
    assert_equal @review.id, @task.reload.column_id
  end

  test "approval is a no-op when the task is not pending review" do
    patch task_approval_url(@task)
    assert_response :see_other
    assert_equal @backlog.id, @task.reload.column_id
  end

  test "moving a task into an agent column enqueues a TriggerColumnJob" do
    assert_enqueued_with(job: TriggerColumnJob, args: [ @task.id ]) do
      post task_transition_url(@task), params: { target_column_id: @in_progress.id }
    end
  end

  test "moving a task into a manual column does not enqueue any TriggerColumnJob" do
    assert_no_enqueued_jobs(only: TriggerColumnJob) do
      post task_transition_url(@task), params: { target_column_id: @review.id }
    end
  end
end
