require "test_helper"

class Roles::HiringTest < ActiveSupport::TestCase
  setup do
    @project = projects(:acme)
    @ceo = roles(:ceo)
    @cmo = roles(:cmo)
  end

  # --- department_template ---

  test "CMO resolves to marketing department template" do
    template = @cmo.department_template
    assert_not_nil template
    assert_equal "marketing", template.key
  end

  test "CEO has no department template (it is the project root)" do
    assert_nil @ceo.department_template
  end

  # --- hirable_roles ---

  test "CMO can hire roles from marketing template below its level" do
    hirable = @cmo.hirable_roles
    hirable_titles = hirable.map(&:title)

    assert_includes hirable_titles, "Marketing Planner"
    assert_includes hirable_titles, "Marketing Manager"
    assert_not_includes hirable_titles, "CMO"
  end

  test "hirable_roles excludes roles that already exist in the project" do
    @project.roles.create!(title: "Marketing Planner", description: "Planner", parent: @cmo, role_category: role_categories(:executor))

    hirable = @cmo.hirable_roles
    hirable_titles = hirable.map(&:title)

    assert_not_includes hirable_titles, "Marketing Planner"
  end

  test "CEO returns empty hirable_roles (no department template)" do
    assert_empty @ceo.hirable_roles
  end

  # --- can_hire? ---

  test "CMO can hire Marketing Planner" do
    assert @cmo.can_hire?("Marketing Planner")
  end

  test "CMO cannot hire CMO (same level)" do
    assert_not @cmo.can_hire?("CMO")
  end

  test "CMO cannot hire nonexistent role" do
    assert_not @cmo.can_hire?("Janitor")
  end

  # --- hire! with auto_hire_enabled ---

  test "hire! creates subordinate role when auto_hire_enabled" do
    @cmo.update!(auto_hire_enabled: true)

    assert_difference "Role.count", 1 do
      new_role = @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)

      assert_equal "Marketing Planner", new_role.title
      assert_equal @cmo, new_role.parent
      assert_equal @cmo.adapter_type, new_role.adapter_type
      assert_equal @cmo.adapter_config, new_role.adapter_config
      assert_equal 20000, new_role.budget_cents
      assert_equal @project, new_role.project
      assert new_role.idle?
    end
  end

  test "hire! records audit event when auto_hire_enabled" do
    @cmo.update!(auto_hire_enabled: true)

    assert_difference "AuditEvent.count", 1 do
      @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)
    end

    event = AuditEvent.last
    assert_equal "role_hired", event.action
    assert_equal "Marketing Planner", event.metadata["hired_role_title"]
  end

  test "hire! inherits working_directory from hiring role" do
    @cmo.update!(auto_hire_enabled: true, working_directory: "/projects/website")

    new_role = @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)

    assert_equal "/projects/website", new_role.working_directory
  end

  test "hire! raises when budget_cents exceeds own budget" do
    @cmo.update!(auto_hire_enabled: true)

    error = assert_raises(Roles::Hiring::HiringError) do
      @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 999_999)
    end
    assert_match(/budget/i, error.message)
  end

  test "hire! raises for non-hirable role title" do
    @cmo.update!(auto_hire_enabled: true)

    error = assert_raises(Roles::Hiring::HiringError) do
      @cmo.hire!(template_role_title: "CEO", budget_cents: 10000)
    end
    assert_match(/cannot hire/i, error.message)
  end

  test "hire! raises when role already exists in project" do
    @cmo.update!(auto_hire_enabled: true)
    @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)

    error = assert_raises(Roles::Hiring::HiringError) do
      @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)
    end
    assert_match(/already exists/i, error.message)
  end

  # --- hire! without auto_hire_enabled (pending approval) ---

  test "hire! creates pending hire and blocks agent when auto_hire disabled" do
    assert_not @cmo.auto_hire_enabled?

    assert_difference "PendingHire.count", 1 do
      result = @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)
      assert_kind_of PendingHire, result
      assert result.pending?
    end

    @cmo.reload
    assert @cmo.pending_approval?
  end

  test "hire! notifies admins when pending approval" do
    assert_difference "Notification.count" do
      @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)
    end

    notification = Notification.last
    assert_equal "hire_approval_requested", notification.action
    assert_equal "Marketing Planner", notification.metadata["requested_hire"]
  end

  test "hire! records audit event when pending approval" do
    assert_difference "AuditEvent.count", 1 do
      @cmo.hire!(template_role_title: "Marketing Planner", budget_cents: 20000)
    end

    event = AuditEvent.last
    assert_equal "hire_requested", event.action
  end

  # --- execute_hire! (called after approval) ---

  test "execute_hire! creates the role from pending hire data" do
    pending_hire = PendingHire.create!(
      role: @cmo,
      project: @project,
      template_role_title: "Marketing Planner",
      budget_cents: 20000
    )

    assert_difference "Role.count", 1 do
      new_role = @cmo.execute_hire!(pending_hire)
      assert_equal "Marketing Planner", new_role.title
      assert_equal @cmo, new_role.parent
    end
  end
end
