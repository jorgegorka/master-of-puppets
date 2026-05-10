require "test_helper"

class ColumnTest < ActiveSupport::TestCase
  test "agent_driven scope includes only agent columns" do
    project = projects(:acme)
    assert_equal 1, project.columns.agent_driven.count
    assert_equal "In Progress", project.columns.agent_driven.first.name
  end

  test "manual_only scope excludes agent column" do
    project = projects(:acme)
    assert_not_includes project.columns.manual_only, columns(:acme_in_progress)
  end

  test "ordered returns columns by position" do
    project = projects(:acme)
    positions = project.columns.ordered.pluck(:position)
    assert_equal positions.sort, positions
  end

  test "name uniqueness is scoped to project" do
    project = projects(:acme)
    dup = project.columns.build(name: "Backlog", transition_policy: "manual")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "agent column auto-generates api_token before validation" do
    project = projects(:acme)
    column = project.columns.build(
      name: "Auto Token",
      transition_policy: "agent",
      position: 99
    )
    assert column.valid?
    assert_not_nil column.api_token
  end

  test "manual columns nullify agent fields on save" do
    project = projects(:acme)
    column = project.columns.build(
      name: "Cleaned",
      transition_policy: "manual",
      position: 100,
      job_spec: "should be cleared",
      adapter_type: "claude_local",
      adapter_config: { "model" => "x" },
      budget_cents: 1000,
      api_token: "should-be-cleared"
    )
    column.valid?
    assert_nil column.job_spec
    assert_nil column.adapter_type
    assert_equal({}, column.adapter_config)
    assert_equal 0, column.budget_cents
    assert_nil column.api_token
  end

  test "regenerate_api_token! rotates token on agent columns" do
    column = columns(:acme_in_progress)
    old = column.api_token
    column.regenerate_api_token!
    refute_equal old, column.reload.api_token
  end

  test "regenerate_api_token! raises on manual columns" do
    column = columns(:acme_backlog)
    assert_raises(RuntimeError) { column.regenerate_api_token! }
  end

  test "agent_configured? requires adapter_type" do
    project = projects(:acme)
    unconfigured = project.columns.create!(
      name: "Unconfigured",
      transition_policy: "agent",
      position: 99
    )
    assert_not unconfigured.agent_configured?
    refute unconfigured.runnable?
  end

  test "kind validates only allowed values" do
    project = projects(:acme)
    column = project.columns.build(name: "Weird", transition_policy: "manual", position: 99, kind: "bogus")
    assert_not column.valid?
    assert column.errors[:kind].any?
  end

  test "system_key uniqueness scoped to project" do
    project = projects(:acme)
    dup = project.columns.build(name: "Another Backlog", transition_policy: "manual", position: 99, system_key: "backlog")
    assert_not dup.valid?
  end
end
