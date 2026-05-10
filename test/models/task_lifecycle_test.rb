require "test_helper"

class TaskLifecycleTest < ActiveSupport::TestCase
  setup do
    @project = projects(:acme)
  end

  test "active includes tasks in non-terminal columns" do
    active_titles = @project.tasks.active.pluck(:title)
    assert_includes active_titles, tasks(:fix_login_bug).title
    assert_includes active_titles, tasks(:write_tests).title
    assert_includes active_titles, tasks(:pending_review_task).title
    refute_includes active_titles, tasks(:completed_task).title
    refute_includes active_titles, tasks(:eval_ready_task).title
  end

  test "completed includes only tasks in done-kind columns" do
    completed = @project.tasks.completed.pluck(:title)
    assert_includes completed, tasks(:completed_task).title
    assert_includes completed, tasks(:eval_ready_task).title
    refute_includes completed, tasks(:fix_login_bug).title
    refute_includes completed, tasks(:pending_review_task).title
  end

  test "cancelled selects tasks in cancelled-kind columns" do
    initial = @project.tasks.cancelled.count
    target = tasks(:fix_login_bug)
    target.update!(column: columns(:acme_cancelled), entered_column_at: Time.current, position: 1)
    assert_equal initial + 1, @project.tasks.cancelled.count
    assert_includes @project.tasks.cancelled, target
  end

  test "blocked selects tasks in the blocked system column" do
    target = tasks(:fix_login_bug)
    target.update!(column: columns(:acme_blocked), entered_column_at: Time.current, position: 1)
    assert_includes @project.tasks.blocked, target
    refute_includes @project.tasks.blocked, tasks(:design_homepage)
  end

  test "pending_human_review selects tasks in review-kind columns" do
    pending = @project.tasks.pending_human_review.pluck(:title)
    assert_includes pending, tasks(:pending_review_task).title
    refute_includes pending, tasks(:fix_login_bug).title
    refute_includes pending, tasks(:completed_task).title
  end

  test "predicates mirror the scopes for a single record" do
    assert tasks(:completed_task).completed?
    assert tasks(:completed_task).terminal?
    refute tasks(:completed_task).pending_review?

    assert tasks(:pending_review_task).pending_review?
    refute tasks(:pending_review_task).completed?

    assert_not tasks(:fix_login_bug).terminal?
    refute tasks(:fix_login_bug).blocked?
    refute tasks(:fix_login_bug).cancelled?
  end

  test "moving a task between columns flips it between scopes" do
    task = tasks(:fix_login_bug)
    refute_includes @project.tasks.completed, task
    refute_includes @project.tasks.blocked, task

    task.update!(column: columns(:acme_blocked), entered_column_at: Time.current, position: 1)
    assert_includes @project.tasks.blocked, task
    # `blocked` is non-terminal: it stays inside the `active` scope by design.
    assert_includes @project.tasks.active, task

    task.update!(column: columns(:acme_done), entered_column_at: Time.current, position: 1)
    assert_includes @project.tasks.completed, task
    assert_not_includes @project.tasks.blocked, task
    assert_not_includes @project.tasks.active, task
    assert task.reload.terminal?
  end
end
