require "test_helper"

class TriggerColumnJobTest < ActiveJob::TestCase
  test "no-op for missing task" do
    assert_nothing_raised { TriggerColumnJob.perform_now(0) }
  end

  test "no-op for task in manual column" do
    task = tasks(:write_tests)
    assert_no_difference("Run.count") do
      TriggerColumnJob.perform_now(task.id)
    end
  end

  test "creates throttled run when at capacity" do
    task = tasks(:design_homepage)
    project = task.project
    project.update!(max_concurrent_agents: 0)
    task.column.update!(max_concurrent_runs: 1)
    Run.where(project: project).destroy_all
    task.column.runs.create!(project: project, task: tasks(:fix_login_bug), status: :running, trigger_type: "manual")

    assert_difference("Run.count", +1) do
      TriggerColumnJob.perform_now(task.id)
    end
    assert_equal "throttled", Run.last.status
  end
end
