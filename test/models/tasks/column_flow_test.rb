require "test_helper"

module Tasks
  class ColumnFlowTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "enter_column! updates column, position, entered_column_at" do
      task = tasks(:design_homepage)
      target = columns(:acme_review)
      next_pos = (target.tasks.maximum(:position) || 0) + 1

      task.enter_column!(target, actor: users(:one), kind: :manual_move, reason: "manual move")

      assert_equal target.id, task.reload.column_id
      assert_equal next_pos, task.position
      assert_in_delta Time.current, task.entered_column_at, 5
    end

    test "enter_column! creates audit event" do
      task = tasks(:write_tests)
      target = columns(:acme_in_progress)

      assert_difference("AuditEvent.where(action: 'task_manual_moved').count", +1) do
        task.enter_column!(target, actor: users(:one), kind: :manual_move)
      end
    end

    test "enter_column! enqueues TriggerColumnJob for agent target" do
      task = tasks(:write_tests)
      target = columns(:acme_in_progress)

      assert_enqueued_with(job: TriggerColumnJob, args: [ task.id ]) do
        task.enter_column!(target, actor: users(:one), kind: :manual_move)
      end
    end

    test "enter_column! does not enqueue job for manual target" do
      task = tasks(:write_tests)
      target = columns(:acme_review)

      assert_no_enqueued_jobs(only: TriggerColumnJob) do
        task.enter_column!(target, actor: users(:one), kind: :manual_move)
      end
    end

    test "enter_column! sets completed_at when entering terminal column" do
      task = tasks(:write_tests)
      target = columns(:acme_done)

      task.enter_column!(target, actor: users(:one), kind: :manual_move)
      assert_not_nil task.reload.completed_at
    end

    test "enter_column! clears completed_at when leaving terminal column" do
      task = tasks(:completed_task)
      target = columns(:acme_in_progress)
      task.enter_column!(target, actor: users(:one), kind: :manual_move)
      assert_nil task.reload.completed_at
    end

    test "cancel! moves task to cancelled column" do
      task = tasks(:write_tests)
      task.cancel!(actor: users(:one), reason: "obsolete")
      assert_equal columns(:acme_cancelled).id, task.reload.column_id
      assert task.cancelled?
    end
  end
end
