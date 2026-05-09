require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    sign_in_as(@user)
    post project_switch_url(@project)
    @design_task = tasks(:design_homepage)
    @widgets_task = tasks(:widgets_task)
    @ceo = roles(:ceo)
    @cto = roles(:cto)
    @developer = roles(:developer)
  end

  # --- Index ---

  test "should get index" do
    get tasks_url
    assert_response :success
    assert_select ".task-card", minimum: 1
  end

  test "should only show tasks for current project" do
    get tasks_url
    assert_response :success
    assert_select ".task-card__title a", text: "Design homepage"
    assert_select ".task-card__title a", text: "Update widget catalog", count: 0
  end

  test "index renders kanban columns for each status" do
    get tasks_url
    assert_response :success
    Task::BOARD_COLUMNS.each do |status|
      next if status == "cancelled"
      assert_select ".kanban__column[data-status=?]", status
    end
  end

  test "index hides cancelled column by default" do
    cancelled = Task.create!(title: "Cancelled task", project: @project, creator: @ceo, status: :cancelled)
    get tasks_url
    assert_response :success
    assert_select ".kanban__column[data-status='cancelled']", count: 0
    assert_select ".task-card__title a", text: cancelled.title, count: 0
  end

  test "index shows cancelled column when show_cancelled=1" do
    cancelled = Task.create!(title: "Cancelled task", project: @project, creator: @ceo, status: :cancelled)
    get tasks_url, params: { show_cancelled: "1" }
    assert_response :success
    assert_select ".kanban__column[data-status='cancelled']"
    assert_select ".task-card__title a", text: cancelled.title
  end

  test "index filters by assignee_id" do
    get tasks_url, params: { assignee_id: @cto.id }
    assert_response :success
    # @cto-assigned tasks visible
    assert_select ".task-card__title a", text: @design_task.title
    # @developer-only tasks (no @cto assignment) hidden
    assert_select ".task-card__title a", text: tasks(:fix_login_bug).title, count: 0
  end

  test "index filters by parent_task_id" do
    get tasks_url, params: { parent_task_id: @design_task.id }
    assert_response :success
    # subtask of design_task is shown
    assert_select ".task-card__title a", text: tasks(:subtask_one).title
    # design_task itself (parent) is hidden
    assert_select ".task-card__title a", text: @design_task.title, count: 0
  end

  test "index filters by overdue" do
    overdue = Task.create!(title: "Overdue uniq", project: @project, creator: @ceo, status: :open, due_at: 2.days.ago)
    Task.create!(title: "Future uniq", project: @project, creator: @ceo, status: :open, due_at: 2.days.from_now)
    get tasks_url, params: { overdue: "1" }
    assert_response :success
    assert_select ".task-card__title a", text: overdue.title
    assert_select ".task-card__title a", text: "Future uniq", count: 0
  end

  # --- Show ---

  test "should show task" do
    get task_url(@design_task)
    assert_response :success
    assert_select "h1", "Design homepage"
  end

  test "should not show task from another project" do
    get task_url(@widgets_task)
    assert_redirected_to root_url
  end

  # --- New / Create ---

  test "should redirect new when project has no roles" do
    @project.tasks.destroy_all
    @project.roles.destroy_all
    get new_task_url
    assert_redirected_to roles_url
  end

  test "should redirect create when project has no roles" do
    @project.tasks.destroy_all
    @project.roles.destroy_all
    assert_no_difference("Task.count") do
      post tasks_url, params: { task: { title: "No roles" } }
    end
    assert_redirected_to roles_url
  end

  test "should get new task form" do
    get new_task_url
    assert_response :success
    assert_select "form"
  end

  test "should create task" do
    assert_difference("Task.count", 1) do
      post tasks_url, params: {
        task: {
          title: "New test task",
          description: "A task for testing",
          priority: "medium",
          creator_id: @ceo.id
        }
      }
    end
    task = Task.order(:created_at).last
    assert_equal "New test task", task.title
    assert_equal "medium", task.priority
    assert_equal @project, task.project
    assert_equal @ceo, task.creator
    assert_redirected_to task_url(task)
  end

  test "should create task with assignee" do
    assert_difference("Task.count", 1) do
      post tasks_url, params: {
        task: {
          title: "Assigned task",
          priority: "high",
          creator_id: @ceo.id,
          assignee_id: @cto.id
        }
      }
    end
    task = Task.order(:created_at).last
    assert_equal @cto, task.assignee
  end

  test "should create audit events on task creation" do
    assert_difference("AuditEvent.count", 2) do
      post tasks_url, params: {
        task: {
          title: "Audit test task",
          priority: "low",
          creator_id: @ceo.id
        }
      }
    end
    task = Task.order(:created_at).last
    assert task.audit_events.find_by(action: "created")
    assert task.audit_events.find_by(action: "assigned"), "assigns to creator by default"
  end

  test "should create two audit events when task created with assignee" do
    assert_difference("AuditEvent.count", 2) do
      post tasks_url, params: {
        task: {
          title: "Assigned task with audit",
          priority: "medium",
          creator_id: @ceo.id,
          assignee_id: @cto.id
        }
      }
    end
    task = Task.order(:created_at).last
    assert task.audit_events.find_by(action: "created")
    assert task.audit_events.find_by(action: "assigned")
  end

  test "should not create task with blank title" do
    assert_no_difference("Task.count") do
      post tasks_url, params: {
        task: { title: "", priority: "medium" }
      }
    end
    assert_response :unprocessable_entity
  end

  # --- Edit / Update ---

  test "should get edit form" do
    get edit_task_url(@design_task)
    assert_response :success
    assert_select "form"
  end

  test "should update task" do
    patch task_url(@design_task), params: {
      task: { title: "Updated title", description: "Updated description" }
    }
    assert_redirected_to task_url(@design_task)
    @design_task.reload
    assert_equal "Updated title", @design_task.title
    assert_equal "Updated description", @design_task.description
  end

  test "should create audit event on status change" do
    assert_difference("AuditEvent.count", 1) do
      patch task_url(@design_task), params: {
        task: { status: "blocked" }
      }
    end
    event = @design_task.audit_events.reload.where(action: "status_changed").last
    assert_not_nil event
    assert_equal "blocked", event.metadata["to"]
  end

  test "should create audit event on assignment change" do
    assert_difference("AuditEvent.count", 1) do
      patch task_url(tasks(:write_tests)), params: {
        task: { assignee_id: @developer.id }
      }
    end
    event = tasks(:write_tests).audit_events.reload.find_by(action: "assigned")
    assert_not_nil event
    assert_equal @developer.title, event.metadata["assignee_name"]
  end

  test "should not update task with blank title" do
    patch task_url(@design_task), params: { task: { title: "" } }
    assert_response :unprocessable_entity
  end

  # --- Destroy ---

  test "should destroy task" do
    assert_difference("Task.count", -1) do
      delete task_url(tasks(:write_tests))
    end
    assert_redirected_to tasks_url
  end

  # --- Auth / Scoping ---

  test "should redirect unauthenticated user" do
    sign_out
    get tasks_url
    assert_redirected_to new_session_url
  end

  test "should redirect user without project" do
    user_without_project = User.create!(
      email_address: "taskless@example.com",
      password: "password",
      password_confirmation: "password"
    )
    sign_in_as(user_without_project)
    get tasks_url
    assert_redirected_to new_onboarding_project_url
  end
end
