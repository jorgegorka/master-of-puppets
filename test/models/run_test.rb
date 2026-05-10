require "test_helper"

class RunTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "active scope includes queued, running, throttled" do
    statuses = runs(
      :queued_run_for_design_homepage,
      :running_run_for_fix_login_bug,
      :throttled_run_for_write_tests
    ).map(&:status)
    Run.active.each { |r| assert_includes %w[queued running throttled], r.status }
    assert (Run.active.pluck(:status).sort & %w[queued running throttled]).any?
  end

  test "terminal scope includes completed and failed" do
    assert_includes Run.terminal, runs(:completed_run_for_completed_task)
    assert_includes Run.terminal, runs(:failed_run_for_eval_ready_task)
  end

  test "partial unique index forbids second active run on same column+task" do
    column = columns(:acme_in_progress)
    task = tasks(:design_homepage)
    # queued_run_for_design_homepage already exists
    assert_raises(ActiveRecord::RecordNotUnique) do
      column.runs.create!(project: column.project, task: task, status: :queued, trigger_type: "task_entered")
    end
  end

  test "second run allowed once prior is terminal" do
    column = columns(:acme_in_progress)
    task = tasks(:completed_task)
    # completed_run_for_completed_task is terminal
    new_run = column.runs.create!(project: column.project, task: task, status: :queued, trigger_type: "task_entered")
    assert new_run.persisted?
  end

  test "start! transitions queued to running" do
    run = runs(:queued_run_for_design_homepage)
    run.start!
    assert run.reload.running?
    assert_not_nil run.started_at
    assert_not_nil run.last_activity_at
  end

  test "finish! sets status and finished_at" do
    run = runs(:running_run_for_fix_login_bug)
    run.finish!(status: :completed)
    assert run.reload.completed?
    assert_not_nil run.finished_at
  end

  test "finish! triggers dispatch_next_throttled_run!" do
    project = projects(:acme)
    column = columns(:acme_in_progress)
    project.update!(max_concurrent_agents: 1)
    Run.where(project: project).destroy_all

    running = column.runs.create!(project: project, task: tasks(:design_homepage), status: :running, trigger_type: "manual")
    throttled = column.runs.create!(project: project, task: tasks(:fix_login_bug), status: :throttled, trigger_type: "task_entered")

    assert_enqueued_with(job: ExecuteColumnJob, args: [ throttled.id ]) do
      running.finish!(status: :completed)
    end
    assert throttled.reload.queued?
  end

  test "cancel! moves to cancelled" do
    run = runs(:running_run_for_fix_login_bug)
    run.cancel!
    assert run.reload.cancelled?
    assert_not_nil run.finished_at
  end
end
