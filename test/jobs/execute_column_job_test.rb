require "test_helper"

class ExecuteColumnJobTest < ActiveJob::TestCase
  setup do
    @run = runs(:queued_run_for_design_homepage)
  end

  test "no-op for missing run" do
    assert_nothing_raised { ExecuteColumnJob.perform_now(0) }
  end

  test "no-op when run already terminal" do
    run = runs(:completed_run_for_completed_task)
    assert_nothing_raised { ExecuteColumnJob.perform_now(run.id) }
    assert run.reload.completed?
  end

  test "fails the run when column not runnable" do
    @run.column.update_columns(adapter_type: nil)
    ExecuteColumnJob.perform_now(@run.id)
    assert @run.reload.failed?
  end

  test "invokes adapter with kwargs run, prompt, session_id" do
    captured = {}
    fake_adapter = Class.new do
      define_singleton_method(:execute) do |run:, prompt:, session_id: nil|
        captured[:run] = run
        captured[:prompt] = prompt
        captured[:session_id] = session_id
      end
    end

    AdapterRegistry.singleton_class.alias_method :original_for, :for
    AdapterRegistry.define_singleton_method(:for) { |_type| fake_adapter }

    begin
      ExecuteColumnJob.perform_now(@run.id)
    ensure
      AdapterRegistry.singleton_class.alias_method :for, :original_for
    end

    assert_equal @run.id, captured[:run]&.id
    assert captured[:prompt].is_a?(String) && captured[:prompt].length > 0
  end
end
