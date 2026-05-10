require "test_helper"

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    sign_in_as(@user)
    cookies[:project_id] = @project.id
    @project.memberships.find_or_create_by(user: @user) { |m| m.role = :owner }
  end

  test "index lists project columns" do
    get columns_url
    assert_response :success
    assert_select "h1", "Columns"
  end

  test "new shows form" do
    get new_column_url
    assert_response :success
  end

  test "create with valid manual params" do
    assert_difference("@project.columns.count", +1) do
      post columns_url, params: { column: { name: "Test", transition_policy: "manual", position: 99 } }
    end
    assert_redirected_to columns_path
  end

  test "create with invalid agent column missing fields succeeds with policy=agent (unconfigured allowed)" do
    # Per Column#agent_configured? — agent without adapter_type is valid (not yet configured).
    assert_difference("@project.columns.count", +1) do
      post columns_url, params: { column: { name: "Empty Agent", transition_policy: "agent", position: 99 } }
    end
    assert_redirected_to columns_path
  end

  test "update name" do
    column = columns(:acme_backlog)
    patch column_url(column), params: { column: { name: "Renamed Backlog" } }
    assert_redirected_to columns_path
    assert_equal "Renamed Backlog", column.reload.name
  end

  test "destroy refused for system columns" do
    column = columns(:acme_backlog)
    delete column_url(column)
    assert_redirected_to columns_path
    assert column.reload.persisted?
  end

  test "destroy refused when column has tasks" do
    project = projects(:acme)
    column = project.columns.create!(name: "Empty One", transition_policy: "manual", position: 99)
    column.tasks.create!(title: "X", creator: @user, project: project, entered_column_at: Time.current, position: 1)
    delete column_url(column)
    assert_redirected_to columns_path
    assert column.reload.persisted?
  end
end
