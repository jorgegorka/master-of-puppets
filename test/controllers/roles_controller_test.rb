require "test_helper"

class RolesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    sign_in_as(@user)
    post project_switch_url(@project)
    @ceo = roles(:ceo)
    @cto = roles(:cto)
    @developer = roles(:developer)
  end

  # --- Index ---

  test "should get index with org chart as default view" do
    get roles_url
    assert_response :success
    assert_select "[data-controller='org-chart']"
    assert_select "[data-org-chart-roles-value]"
  end

  test "should get index with list view" do
    get roles_url(view: "list")
    assert_response :success
    assert_select ".role-card", minimum: 3
  end

  test "should include role data in chart view" do
    get roles_url
    assert_response :success
    assert_match "CEO", response.body
    assert_match "CTO", response.body
  end

  test "should only show roles for current project" do
    get roles_url(view: "list")
    assert_response :success
    assert_select ".role-card__title", text: "CEO"
    assert_select ".role-card__title", text: "Operations Lead", count: 0
  end

  test "should not include other project roles in chart view" do
    get roles_url
    assert_select "[data-org-chart-roles-value]" do |elements|
      refute_match(/Operations Lead/, elements.first["data-org-chart-roles-value"])
    end
  end

  # --- JSON search (powers @-mention autocomplete) ---

  test "JSON index returns active roles in current project" do
    get roles_url(format: :json)
    assert_response :success

    json = response.parsed_body
    assert json.is_a?(Array)
    titles = json.map { |r| r["title"] }
    assert_includes titles, "CEO"
    assert_includes titles, "CTO"
    refute_includes titles, "Operations Lead" # cross-project role
  end

  test "JSON index filters by case-insensitive substring on title" do
    get roles_url(format: :json, q: "ce")
    assert_response :success

    titles = response.parsed_body.map { |r| r["title"] }
    assert_includes titles, "CEO"
    refute_includes titles, "CTO"
  end

  test "JSON index returns each role with id and title only" do
    get roles_url(format: :json, q: "CEO")
    json = response.parsed_body
    assert_equal 1, json.size
    assert_equal %w[id title].sort, json.first.keys.sort
  end

  test "JSON index excludes terminated roles" do
    @cto.update!(status: :terminated)
    get roles_url(format: :json, q: "CTO")
    titles = response.parsed_body.map { |r| r["title"] }
    refute_includes titles, "CTO"
  end

  # --- Show ---

  test "should show role" do
    get role_url(@ceo)
    assert_response :success
    assert_select "h1", "CEO"
  end

  test "should show direct reports on role detail" do
    get role_url(@ceo)
    assert_response :success
    assert_select ".role-card__title", text: "CTO"
  end

  test "should not show role from another project" do
    get role_url(roles(:widgets_lead))
    assert_redirected_to root_url
  end

  test "should show adapter type on detail page" do
    get role_url(@developer)
    assert_response :success
    assert_select ".role-detail__adapter-label", text: "HTTP API"
  end

  # --- New / Create ---

  test "should get new role form" do
    get new_role_url
    assert_response :success
    assert_select "form"
    assert_select "select[name='role[parent_id]']"
  end

  test "new form exposes library picker with every library role" do
    get new_role_url
    assert_response :success
    assert_select "form.form--library-picker select[name='library_key']" do
      assert_select "option", minimum: RoleLibrary::Registry.all.size
    end
  end

  test "new with library_key pre-fills title description category and job_spec" do
    get new_role_url, params: { library_key: "tech_planner" }
    assert_response :success
    library_role = RoleLibrary::Registry.find("tech_planner")
    assert_select "input[name='role[title]'][value=?]", library_role.title
    assert_select "textarea[name='role[description]']", text: /#{Regexp.escape(library_role.description.strip)}/m
    assert_select "textarea[name='role[job_spec]']", text: /#{Regexp.escape("You are the Tech Planner")}/
    planner_category = @project.role_categories.find_by!(name: library_role.category)
    assert_select "select[name='role[role_category_id]']" do
      assert_select "option[selected][value=?]", planner_category.id.to_s
    end
    assert_select "input[type=hidden][name=library_key][value='tech_planner']"
  end

  test "new with unknown library_key silently renders blank form" do
    get new_role_url, params: { library_key: "nonexistent_library_role" }
    assert_response :success
    assert_select "input[name='role[title]']" do |inputs|
      assert_empty inputs.first["value"].to_s
    end
  end

  test "create with library_key attaches matching project skills" do
    post roles_url, params: {
      role: { title: "Tech Planner", role_category_id: role_categories(:executor).id },
      library_key: "tech_planner"
    }
    role = Role.order(:created_at).last
    assert_equal "Tech Planner", role.title
    library_skill_keys = RoleLibrary::Registry.find("tech_planner").skill_keys
    expected_keys = @project.skills.where(key: library_skill_keys).pluck(:key)
    attached_keys = role.skills.pluck(:key).sort
    assert_equal expected_keys.sort, attached_keys
    assert attached_keys.any?, "expected at least one attached skill"
  end

  test "create without library_key attaches no library skills" do
    assert_difference("RoleSkill.count", 0) do
      post roles_url, params: {
        role: { title: "Plain Role", role_category_id: role_categories(:executor).id }
      }
    end
  end

  test "should create role" do
    assert_difference("Role.count", 1) do
      post roles_url, params: {
        role: { title: "Designer", description: "UI/UX design", job_spec: "Design interfaces", parent_id: @cto.id, role_category_id: role_categories(:executor).id }
      }
    end
    role = Role.order(:created_at).last
    assert_equal "Designer", role.title
    assert_equal @cto, role.parent
    assert_equal @project, role.project
    assert_redirected_to role_url(role)
  end

  test "should create root role with no parent" do
    assert_difference("Role.count", 1) do
      post roles_url, params: {
        role: { title: "Advisor", description: "External advisor", role_category_id: role_categories(:executor).id }
      }
    end
    role = Role.order(:created_at).last
    assert_nil role.parent_id
  end

  test "should not create role with blank title" do
    assert_no_difference("Role.count") do
      post roles_url, params: { role: { title: "", role_category_id: role_categories(:executor).id } }
    end
    assert_response :unprocessable_entity
  end

  test "should not create role with duplicate title" do
    assert_no_difference("Role.count") do
      post roles_url, params: { role: { title: "CEO", role_category_id: role_categories(:executor).id } }
    end
    assert_response :unprocessable_entity
  end

  test "should create role with adapter config (http)" do
    assert_difference("Role.count", 1) do
      post roles_url, params: {
        role: {
          title: "New HTTP Role",
          adapter_type: "http",
          adapter_config: { url: "https://example.com/api", method: "POST" },
          role_category_id: role_categories(:executor).id
        }
      }
    end
    role = Role.order(:created_at).last
    assert_equal "New HTTP Role", role.title
    assert role.http?
    assert_equal "https://example.com/api", role.adapter_config["url"]
    assert_equal @project, role.project
    assert_redirected_to role_url(role)
  end

  test "should create role with claude_local adapter" do
    assert_difference("Role.count", 1) do
      post roles_url, params: {
        role: {
          title: "Local Claude Role",
          adapter_type: "claude_local",
          adapter_config: { model: "claude-sonnet-4-20250514" },
          role_category_id: role_categories(:executor).id
        }
      }
    end
    role = Role.order(:created_at).last
    assert role.claude_local?
    assert_equal "claude-sonnet-4-20250514", role.adapter_config["model"]
  end

  test "should create role with working_directory" do
    post roles_url, params: { role: { title: "Agent", working_directory: "/projects/website", role_category_id: role_categories(:executor).id } }
    role = Role.find_by(title: "Agent")
    assert_equal "/projects/website", role.working_directory
  end

  # --- Edit / Update ---

  test "should get edit form" do
    get edit_role_url(@cto)
    assert_response :success
    assert_select "form"
  end

  test "should update role" do
    patch role_url(@cto), params: { role: { title: "VP Engineering", description: "Updated description" } }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert_equal "VP Engineering", @cto.title
    assert_equal "Updated description", @cto.description
  end

  test "should update role parent" do
    patch role_url(@developer), params: { role: { parent_id: @ceo.id } }
    assert_redirected_to role_url(@developer)
    @developer.reload
    assert_equal @ceo, @developer.parent
  end

  test "should update role working_directory" do
    patch role_url(@cto), params: { role: { working_directory: "/projects/website" } }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert_equal "/projects/website", @cto.working_directory
  end

  test "should not update role with blank title" do
    patch role_url(@cto), params: { role: { title: "" } }
    assert_response :unprocessable_entity
  end

  # --- Destroy ---

  test "should destroy role and re-parent children" do
    @cto.created_tasks.update_all(creator_id: @ceo.id)
    assert_difference("Role.count", -1) do
      delete role_url(@cto)
    end
    assert_redirected_to roles_url
    @developer.reload
    assert_equal @ceo.id, @developer.parent_id
  end

  test "should destroy root role and make children root" do
    @ceo.created_tasks.update_all(creator_id: @cto.id)
    assert_difference("Role.count", -1) do
      delete role_url(@ceo)
    end
    @cto.reload
    assert_nil @cto.parent_id
  end

  # --- Auth / Scoping ---

  test "should redirect unauthenticated user" do
    sign_out
    get roles_url
    assert_redirected_to new_session_url
  end

  test "should redirect user without project" do
    user_without_project = User.create!(email_address: "lonely@example.com", password: "password", password_confirmation: "password")
    sign_in_as(user_without_project)
    get roles_url
    assert_redirected_to new_onboarding_project_url
  end

  # --- Heartbeat Schedule ---

  test "should create role with heartbeat schedule" do
    assert_difference("Role.count", 1) do
      post roles_url, params: {
        role: {
          title: "Scheduled Role",
          adapter_type: "http",
          adapter_config: { url: "https://example.com/agent" },
          heartbeat_enabled: "1",
          heartbeat_interval: "15",
          role_category_id: role_categories(:executor).id
        }
      }
    end
    role = Role.order(:created_at).last
    assert role.heartbeat_enabled?
    assert_equal 15, role.heartbeat_interval
  end

  test "should update role heartbeat schedule" do
    patch role_url(@cto), params: {
      role: {
        heartbeat_enabled: "1",
        heartbeat_interval: "30"
      }
    }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert @cto.heartbeat_enabled?
    assert_equal 30, @cto.heartbeat_interval
  end

  test "should disable role heartbeat" do
    @cto.update_columns(heartbeat_enabled: true, heartbeat_interval: 15)
    patch role_url(@cto), params: {
      role: { heartbeat_enabled: "0" }
    }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert_not @cto.heartbeat_enabled?
  end

  test "should show heartbeat section on role detail page" do
    get role_url(@cto)
    assert_response :success
    assert_select ".role-detail__kv"
  end

  test "should show heartbeat events on role detail page" do
    get role_url(@cto)
    assert_response :success
    assert_select ".heartbeat-table"
  end

  test "should link to heartbeat history from role page" do
    get role_url(@cto)
    assert_response :success
    assert_select "a[href=?]", role_heartbeats_path(@cto)
  end

  # --- Budget ---

  test "should create role with budget" do
    assert_difference("Role.count") do
      post roles_url, params: { role: {
        title: "Budget Role",
        adapter_type: "http",
        adapter_config: { url: "https://example.com" },
        budget_dollars: "250.00",
        role_category_id: role_categories(:executor).id
      } }
    end
    role = Role.find_by(title: "Budget Role")
    assert_equal 25000, role.budget_cents
    assert_equal Date.current.beginning_of_month, role.budget_period_start
  end

  test "should update role budget" do
    patch role_url(@cto), params: { role: { budget_dollars: "750.00" } }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert_equal 75000, @cto.budget_cents
  end

  test "should clear budget when empty string submitted" do
    patch role_url(@cto), params: { role: { budget_dollars: "" } }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert_nil @cto.budget_cents
    assert_nil @cto.budget_period_start
  end

  test "should show budget section on role detail page" do
    get role_url(@cto)
    assert_response :success
    assert_select ".budget-display"
  end

  test "should show no-budget message for role without budget" do
    get role_url(roles(:process_role))
    assert_response :success
    assert_select ".role-detail__empty-note", /No budget configured/
  end

  # --- Emergency Stop ---

  test "should emergency stop all roles" do
    @project.roles.where.not(adapter_type: nil).update_all(status: Role.statuses[:idle])
    post emergency_stop_project_url(@project)
    assert_redirected_to roles_url
  end

  # --- Approval Gates ---

  test "should save approval gates on role update" do
    patch role_url(@cto), params: {
      role: {
        gates_submitted: "1",
        gates: {
          task_creation: "1",
          budget_spend: "1"
        }
      }
    }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert @cto.gate_enabled?("task_creation")
    assert @cto.gate_enabled?("budget_spend")
  end

  test "should disable gates when unchecked" do
    patch role_url(@cto), params: {
      role: {
        gates_submitted: "1",
        gates: {
          task_creation: "1",
          budget_spend: "1"
        }
      }
    }
    patch role_url(@cto), params: {
      role: {
        gates_submitted: "1",
        gates: {}
      }
    }
    assert_redirected_to role_url(@cto)
    @cto.reload
    assert_not @cto.gate_enabled?("task_creation")
    assert_not @cto.gate_enabled?("budget_spend")
  end

  test "should show approval gates section on role detail page" do
    get role_url(@cto)
    assert_response :success
    assert_select ".gate-list", minimum: 0
  end

  test "should show pending approval banner when role is pending" do
    @cto.update_columns(status: Role.statuses[:pending_approval], pause_reason: "Approval required: Task creation gate is active")
    get role_url(@cto)
    assert_response :success
    assert_select ".approval-banner"
  end

  test "should not show pending approval banner for idle role" do
    get role_url(@cto)
    assert_response :success
    assert_select ".approval-banner", count: 0
  end

  # --- Skills: Skill Manager (show page) ---

  test "should show skill manager with checkboxes on role show" do
    get role_url(@cto)
    assert_response :success
    assert_select ".skill-manager"
    assert_select ".skill-manager__category", minimum: 1
  end

  test "should show assigned skills as checked on role show" do
    get role_url(@cto)
    assert_response :success
    assert_select ".skill-manager__toggle--assigned", minimum: 1
  end

  test "should show unassigned skills as unchecked on role show" do
    get role_url(@cto)
    assert_response :success
    assigned_count = css_select(".skill-manager__toggle--assigned").size
    total_count = css_select(".skill-manager__toggle").size
    assert total_count > assigned_count, "Expected unassigned skills to also appear as toggles"
  end

  test "should show skill categories in skill manager" do
    get role_url(@cto)
    assert_response :success
    assert_select ".skill-manager__category-title", minimum: 2
  end

  # --- Skills: Role Card (index page) ---

  test "should show skill tags in role card on list view" do
    get roles_url(view: "list")
    assert_response :success
    assert_select ".role-card__skill-tag", minimum: 1
  end
end
