require "test_helper"

module Projects
  class SpendTest < ActiveSupport::TestCase
    setup do
      @project = projects(:acme)
      @column  = columns(:acme_in_progress)
      Run.where(project: @project).destroy_all
    end

    test "preload_monthly_spend stamps each column with its current-month total" do
      @column.runs.create!(project: @project, task: tasks(:fix_login_bug), trigger_type: "manual",
                           cost_cents: 1_200, status: :completed,
                           started_at: 1.day.ago, finished_at: 1.day.ago)
      @column.runs.create!(project: @project, task: tasks(:design_homepage), trigger_type: "manual",
                           cost_cents: 800, status: :completed,
                           started_at: 2.days.ago, finished_at: 2.days.ago)

      columns = @project.columns.ordered.to_a
      total = @project.preload_monthly_spend(columns)

      target = columns.find { |c| c.id == @column.id }
      assert_equal 2_000, target.preloaded_monthly_spend_cents
      assert_equal 2_000, total

      other = columns.find { |c| c.system_key == "backlog" }
      assert_equal 0, other.preloaded_monthly_spend_cents
    end

    test "preload_monthly_spend ignores runs outside the current month" do
      @column.runs.create!(project: @project, task: tasks(:fix_login_bug), trigger_type: "manual",
                           cost_cents: 9_999, status: :completed,
                           created_at: 35.days.ago, started_at: 35.days.ago, finished_at: 35.days.ago)
      @column.runs.create!(project: @project, task: tasks(:design_homepage), trigger_type: "manual",
                           cost_cents: 250, status: :completed,
                           started_at: 1.hour.ago, finished_at: 1.hour.ago)

      total = @project.preload_monthly_spend([ @column ])
      assert_equal 250, total
      assert_equal 250, @column.preloaded_monthly_spend_cents
    end

    test "preload_monthly_spend returns zero when no columns are passed" do
      assert_equal 0, @project.preload_monthly_spend([])
    end

    test "preload_monthly_spend handles columns with no runs" do
      empty_column = columns(:acme_done)
      total = @project.preload_monthly_spend([ empty_column ])
      assert_equal 0, total
      assert_equal 0, empty_column.preloaded_monthly_spend_cents
    end
  end
end
