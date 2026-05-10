require "test_helper"

module Columns
  class TransitionTest < ActiveSupport::TestCase
    test "advance from agent column resolves next column" do
      task = tasks(:design_homepage)
      run = runs(:running_run_for_fix_login_bug)
      transition = Columns::Transition.new(task: task, actor: run, kind: :advance)
      assert transition.valid?, transition.errors.full_messages.inspect
      assert_equal columns(:acme_review), transition.target_column
    end

    test "advance refused on manual source column" do
      task = tasks(:write_tests)
      transition = Columns::Transition.new(task: task, actor: users(:one), kind: :advance)
      assert_not transition.valid?
      assert_match(/agent transitions require a Run actor on the source agent column|advance only allowed/, transition.errors.full_messages.first)
    end

    test "manual_move from manual column with User actor is valid" do
      task = tasks(:write_tests)
      target = columns(:acme_in_progress)
      transition = Columns::Transition.new(task: task, actor: users(:one), kind: :manual_move, target_column: target)
      assert transition.valid?, transition.errors.full_messages.inspect
    end

    test "manual_move refused from agent column" do
      task = tasks(:design_homepage)
      target = columns(:acme_backlog)
      transition = Columns::Transition.new(task: task, actor: users(:one), kind: :manual_move, target_column: target)
      assert_not transition.valid?
    end

    test "block resolves to project's blocked column" do
      task = tasks(:design_homepage)
      run = runs(:running_run_for_fix_login_bug)
      transition = Columns::Transition.new(task: task, actor: run, kind: :block, reason: "stuck")
      assert transition.valid?, transition.errors.full_messages.inspect
      assert_equal columns(:acme_blocked), transition.target_column
    end

    test "validation does not mutate task" do
      task = tasks(:design_homepage)
      run = runs(:running_run_for_fix_login_bug)
      original_column_id = task.column_id
      Columns::Transition.new(task: task, actor: run, kind: :advance).valid?
      assert_equal original_column_id, task.reload.column_id
    end

    test "advance from review column with User actor is valid" do
      task = tasks(:pending_review_task)
      transition = Columns::Transition.new(task: task, actor: users(:one), kind: :advance)
      assert transition.valid?, transition.errors.full_messages.inspect
      assert_equal columns(:acme_done), transition.target_column
    end

    test "reject from review column with User actor is valid" do
      task = tasks(:pending_review_task)
      transition = Columns::Transition.new(task: task, actor: users(:one), kind: :reject, feedback: "needs more")
      assert transition.valid?, transition.errors.full_messages.inspect
      assert_equal columns(:acme_in_progress), transition.target_column
    end
  end
end
