require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "valid with name" do
    project = Project.new(name: "Test Corp")
    assert project.valid?
  end

  test "invalid without name" do
    project = Project.new(name: nil)
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "has many memberships" do
    project = projects(:acme)
    assert_equal 2, project.memberships.count
  end

  test "has many users through memberships" do
    project = projects(:acme)
    assert_includes project.users, users(:one)
    assert_includes project.users, users(:two)
  end

  test "destroying project destroys memberships" do
    project = projects(:acme)
    assert_difference("Membership.count", -2) do
      project.destroy
    end
  end

  # --- Skill Seeding ---

  test "seed_default_skills! creates builtin skills from YAML files" do
    project = Project.create!(name: "Fresh Corp")
    skill_count = Dir[Rails.root.join("db/seeds/skills/*.yml")].size
    assert_equal skill_count, project.skills.builtin.count
  end

  test "seed_default_skills! is idempotent" do
    project = Project.create!(name: "Idempotent Corp")
    initial_count = project.skills.count
    project.seed_default_skills!
    assert_equal initial_count, project.skills.count
  end

  test "seed_default_columns! seeds six default columns" do
    project = Project.create!(name: "Defaults Corp")
    assert_equal 6, project.columns.count

    columns = project.columns.ordered.to_a
    expected = %w[backlog in_progress review done blocked cancelled]
    assert_equal expected, columns.map(&:system_key)
    assert_equal %w[manual agent manual manual manual manual], columns.map(&:transition_policy)
    assert_equal [ false, false, false, true, false, true ], columns.map(&:terminal)
    assert_equal [ false, false, false, false, true, true ], columns.map(&:hidden_by_default)
  end

  test "seed_default_columns! is idempotent" do
    project = Project.create!(name: "Idempotent Cols")
    initial_count = project.columns.count
    project.seed_default_columns!
    assert_equal initial_count, project.columns.count
  end

  # --- Validation: max_concurrent_agents ---

  test "valid with max_concurrent_agents zero" do
    project = Project.new(name: "Test", max_concurrent_agents: 0)
    assert project.valid?
  end

  test "invalid with negative max_concurrent_agents" do
    project = Project.new(name: "Test", max_concurrent_agents: -1)
    assert_not project.valid?
  end

  # --- Concurrency Limits ---

  test "concurrent_agent_limit_reached? returns false when limit is zero" do
    project = projects(:acme)
    project.update!(max_concurrent_agents: 0)
    Run.where(project: project).destroy_all
    assert_not project.concurrent_agent_limit_reached?
  end

  test "concurrent_agent_limit_reached? returns true at limit" do
    project = projects(:acme)
    project.update!(max_concurrent_agents: 2)
    # Two active runs already exist in fixtures (queued + running on acme_in_progress)
    assert project.concurrent_agent_limit_reached?
  end

  test "concurrent_agent_limit_reached? does not count throttled runs" do
    project = projects(:acme)
    Run.where(project: project).destroy_all
    project.update!(max_concurrent_agents: 2)
    column = columns(:acme_in_progress)
    column.runs.create!(project: project, task: tasks(:fix_login_bug), status: :running, trigger_type: "manual")
    column.runs.create!(project: project, task: tasks(:design_homepage), status: :throttled, trigger_type: "task_entered")
    assert_not project.concurrent_agent_limit_reached?
  end

  # --- Drain Throttled Runs ---

  test "dispatch_next_throttled_run! dispatches oldest throttled run" do
    project = projects(:acme)
    Run.where(project: project).destroy_all
    project.update!(max_concurrent_agents: 1)
    column = columns(:acme_in_progress)

    older = column.runs.create!(project: project, task: tasks(:design_homepage), status: :throttled, trigger_type: "task_entered", created_at: 2.minutes.ago)
    _newer = column.runs.create!(project: project, task: tasks(:fix_login_bug), status: :throttled, trigger_type: "task_entered", created_at: 1.minute.ago)

    project.dispatch_next_throttled_run!
    older.reload

    assert older.queued?, "Oldest throttled run should be queued, got #{older.status}"
  end

  test "dispatch_next_throttled_run! does nothing when at capacity" do
    project = projects(:acme)
    Run.where(project: project).destroy_all
    project.update!(max_concurrent_agents: 1)
    column = columns(:acme_in_progress)

    column.runs.create!(project: project, task: tasks(:fix_login_bug), status: :running, trigger_type: "manual")
    throttled = column.runs.create!(project: project, task: tasks(:design_homepage), status: :throttled, trigger_type: "task_entered")

    project.dispatch_next_throttled_run!
    assert throttled.reload.throttled?
  end

  test "dispatch_next_throttled_run! enqueues ExecuteColumnJob" do
    project = projects(:acme)
    Run.where(project: project).destroy_all
    project.update!(max_concurrent_agents: 1)
    column = columns(:acme_in_progress)

    throttled = column.runs.create!(project: project, task: tasks(:design_homepage), status: :throttled, trigger_type: "task_entered")

    assert_enqueued_with(job: ExecuteColumnJob, args: [ throttled.id ]) do
      project.dispatch_next_throttled_run!
    end
  end
end
