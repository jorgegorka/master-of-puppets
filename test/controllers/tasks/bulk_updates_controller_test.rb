require "test_helper"

class Tasks::BulkUpdatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    @other_project = projects(:widgets)
    @ceo = roles(:ceo)
    @cto = roles(:cto)
    @developer = roles(:developer)
    @design_task = tasks(:design_homepage)
    @login_task  = tasks(:fix_login_bug)
    @widgets_task = tasks(:widgets_task)

    sign_in_as(@user)
    post project_switch_url(@project)
  end

  # --- create / status ---

  test "POST updates status across listed tasks" do
    post bulk_update_path, params: {
      attribute: "status",
      value: "completed",
      ids: "#{@design_task.id},#{@login_task.id}"
    }

    assert_redirected_to tasks_path
    assert_equal "completed", @design_task.reload.status
    assert_equal "completed", @login_task.reload.status
  end

  test "POST writes status_changed audit events on bulk status change" do
    assert_difference("AuditEvent.where(action: 'status_changed').count", 2) do
      post bulk_update_path, params: {
        attribute: "status",
        value: "blocked",
        ids: "#{@design_task.id},#{@login_task.id}"
      }
    end
  end

  test "POST writes assigned audit events with assignee_name on bulk assignee change" do
    post bulk_update_path, params: {
      attribute: "assignee_id",
      value: @developer.id,
      ids: "#{@design_task.id}"
    }
    event = AuditEvent.where(action: "assigned").last
    assert_equal @developer.title, event.metadata["assignee_name"]
  end

  test "POST accepts ids as array" do
    post bulk_update_path, params: {
      attribute: "status",
      value: "blocked",
      ids: [ @design_task.id, @login_task.id ]
    }

    assert_redirected_to tasks_path
    assert_equal "blocked", @design_task.reload.status
    assert_equal "blocked", @login_task.reload.status
  end

  test "POST updates assignee across listed tasks" do
    post bulk_update_path, params: {
      attribute: "assignee_id",
      value: @developer.id,
      ids: "#{@design_task.id},#{@login_task.id}"
    }

    assert_redirected_to tasks_path
    assert_equal @developer.id, @design_task.reload.assignee_id
    assert_equal @developer.id, @login_task.reload.assignee_id
  end

  test "POST updates priority across listed tasks" do
    post bulk_update_path, params: {
      attribute: "priority",
      value: "low",
      ids: "#{@design_task.id},#{@login_task.id}"
    }

    assert_redirected_to tasks_path
    assert_equal "low", @design_task.reload.priority
    assert_equal "low", @login_task.reload.priority
  end

  # --- guards ---

  test "POST with disallowed attribute returns 422" do
    post bulk_update_path, params: {
      attribute: "title",
      value: "Pwned",
      ids: "#{@design_task.id}"
    }

    assert_response :unprocessable_entity
    assert_not_equal "Pwned", @design_task.reload.title
  end

  test "POST with invalid status value does not raise and leaves tasks unchanged" do
    original = @design_task.status
    post bulk_update_path, params: {
      attribute: "status",
      value: "garbage",
      ids: "#{@design_task.id}"
    }

    assert_redirected_to tasks_path
    assert_equal original, @design_task.reload.status
  end

  test "POST with invalid priority value does not raise and leaves tasks unchanged" do
    original = @design_task.priority
    post bulk_update_path, params: {
      attribute: "priority",
      value: "extreme",
      ids: "#{@design_task.id}"
    }

    assert_redirected_to tasks_path
    assert_equal original, @design_task.reload.priority
  end

  test "POST with empty ids returns 422" do
    post bulk_update_path, params: {
      attribute: "status",
      value: "completed",
      ids: ""
    }

    assert_response :unprocessable_entity
  end

  test "POST silently filters out tasks from other projects" do
    post bulk_update_path, params: {
      attribute: "status",
      value: "completed",
      ids: "#{@design_task.id},#{@widgets_task.id}"
    }

    assert_redirected_to tasks_path
    assert_equal "completed", @design_task.reload.status
    assert_not_equal "completed", @widgets_task.reload.status
  end

  test "POST preserves filter params on redirect" do
    post bulk_update_path, params: {
      attribute: "status",
      value: "completed",
      ids: "#{@design_task.id}",
      assignee_id: @cto.id,
      overdue: "1"
    }

    assert_redirected_to tasks_path(assignee_id: @cto.id, overdue: "1")
  end

  # --- destroy ---

  test "DELETE removes the listed tasks" do
    deletable = Task.create!(title: "Bulk delete A", project: @project, creator: @ceo)
    deletable_b = Task.create!(title: "Bulk delete B", project: @project, creator: @ceo)

    assert_difference("Task.count", -2) do
      delete bulk_update_path, params: { ids: "#{deletable.id},#{deletable_b.id}" }
    end
    assert_redirected_to tasks_path
  end

  test "DELETE with empty ids returns 422" do
    delete bulk_update_path, params: { ids: "" }
    assert_response :unprocessable_entity
  end

  # --- auth ---

  test "POST without authentication redirects to login" do
    sign_out
    post bulk_update_path, params: { attribute: "status", value: "completed", ids: "#{@design_task.id}" }
    assert_redirected_to new_session_url
  end
end
