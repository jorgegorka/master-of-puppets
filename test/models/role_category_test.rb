require "test_helper"

class RoleCategoryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:acme)
    @orchestrator = role_categories(:orchestrator)
    Current.project = @project
  end

  teardown do
    Current.project = nil
  end

  # --- Validations ---

  test "valid with name, job_spec, and project" do
    category = RoleCategory.new(name: "Custom", job_spec: "Do custom work.", project: @project)
    assert category.valid?
  end

  test "requires name" do
    category = RoleCategory.new(job_spec: "Do work.", project: @project)
    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test "requires job_spec" do
    category = RoleCategory.new(name: "Custom", project: @project)
    assert_not category.valid?
    assert_includes category.errors[:job_spec], "can't be blank"
  end

  test "name must be unique within project" do
    duplicate = RoleCategory.new(name: "Orchestrator", job_spec: "Duplicate.", project: @project)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this project"
  end

  test "same name allowed in different projects" do
    widgets = projects(:widgets)
    category = RoleCategory.new(name: "Executor", job_spec: "Execute work.", project: widgets)
    assert category.valid?
  end

  # --- Associations ---

  test "has many roles" do
    assert_respond_to @orchestrator, :roles
    assert @orchestrator.roles.count > 0
  end

  test "cannot delete category with assigned roles" do
    assert_not @orchestrator.destroy
    assert_includes @orchestrator.errors[:base].join, "Cannot delete record"
  end

  test "can delete category with no roles" do
    category = RoleCategory.create!(name: "Temporary", job_spec: "Temp.", project: @project)
    assert category.destroy
  end

  # --- Tenantable ---

  test "scoped to current project" do
    scoped = RoleCategory.for_current_project
    assert_includes scoped.map(&:project_id).uniq, @project.id
    assert_not_includes scoped.map(&:project_id).uniq, projects(:widgets).id
  end

  # --- Default definitions ---

  test "default_definitions returns array of category hashes" do
    defs = RoleCategory.default_definitions
    assert_kind_of Array, defs
    assert defs.size >= 2
    assert defs.all? { |d| d.key?("name") && d.key?("job_spec") }
  end

  test "default definitions include Orchestrator and Executor" do
    names = RoleCategory.default_definitions.map { |d| d["name"] }
    assert_includes names, "Orchestrator"
    assert_includes names, "Executor"
  end
end
