require "test_helper"

module Columns
  class TriggeringTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @column = columns(:acme_in_progress)
      @project = @column.project
      Run.where(project: @project).destroy_all
    end

    test "trigger_for spawns queued run when capacity available" do
      @project.update!(max_concurrent_agents: 5)

      run = nil
      assert_difference("Run.count", +1) do
        run = @column.trigger_for(tasks(:design_homepage))
      end
      assert run.queued?
    end

    test "trigger_for inserts throttled run when project at limit" do
      @project.update!(max_concurrent_agents: 1)
      @column.runs.create!(project: @project, task: tasks(:fix_login_bug), status: :running, trigger_type: "manual")

      run = @column.trigger_for(tasks(:design_homepage))
      assert run.throttled?
    end

    test "trigger_for respects column max_concurrent_runs" do
      @project.update!(max_concurrent_agents: 0)  # unlimited project
      @column.update!(max_concurrent_runs: 1)
      @column.runs.create!(project: @project, task: tasks(:fix_login_bug), status: :running, trigger_type: "manual")

      run = @column.trigger_for(tasks(:design_homepage))
      assert run.throttled?
    end

    test "trigger_for treats max_concurrent_runs zero as unlimited" do
      @project.update!(max_concurrent_agents: 0)
      @column.update!(max_concurrent_runs: 0)
      @column.runs.create!(project: @project, task: tasks(:fix_login_bug), status: :running, trigger_type: "manual")

      run = @column.trigger_for(tasks(:design_homepage))
      assert run.queued?, "expected queued, got #{run&.status.inspect}"
    end

    test "trigger_for returns nil for manual columns" do
      assert_nil columns(:acme_backlog).trigger_for(tasks(:write_tests))
    end

    test "trigger_for returns nil for unconfigured agent columns" do
      project = Project.create!(name: "Empty")
      column = project.columns.find_by(system_key: "in_progress")
      task = project.tasks.create!(title: "T", creator: users(:one), column: project.columns.find_by(system_key: "backlog"), entered_column_at: Time.current)
      assert_nil column.trigger_for(task)
    end
  end
end
