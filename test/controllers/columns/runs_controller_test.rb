require "test_helper"

module Columns
  class RunsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @project = projects(:acme)
      sign_in_with_project(@user, @project)
      @column = columns(:acme_in_progress)
    end

    test "index lists this column's runs and ignores other columns' runs" do
      other_column = projects(:widgets).columns.create!(name: "Widget Agent", transition_policy: "agent",
                                                       position: 99, adapter_type: "claude_local",
                                                       adapter_config: { "model" => "claude-sonnet-4-20250514" },
                                                       job_spec: "Spec", success_criteria: "Crit")
      other_run = other_column.runs.create!(project: projects(:widgets), task: tasks(:widgets_task),
                                            status: :running, trigger_type: "manual")

      get column_runs_url(@column)
      assert_response :success
      assert_select "table.runs-table tbody tr"
      refute_match(/##{other_run.id}\b/, response.body)
    end

    test "index scopes runs to the current project" do
      foreign_column = projects(:widgets).columns.first
      get column_runs_url(foreign_column)
      # ApplicationController rescues RecordNotFound to a redirect to root.
      assert_redirected_to root_path
    end

    test "show renders the run partial for a run on this column" do
      run = runs(:running_run_for_fix_login_bug)
      get column_run_url(@column, run)
      assert_response :success
      assert_match(/Run\s*##{run.id}/, response.body)
    end

    test "show redirects to root when run does not belong to the column" do
      run = runs(:running_run_for_fix_login_bug)
      other_column = columns(:acme_backlog)

      get column_run_url(other_column, run)
      assert_redirected_to root_path
    end

    test "show redirects to root when column belongs to another project" do
      foreign_column = projects(:widgets).columns.first
      run = runs(:running_run_for_fix_login_bug)

      get column_run_url(foreign_column, run)
      assert_redirected_to root_path
    end
  end
end
