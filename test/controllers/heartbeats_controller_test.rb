require "test_helper"

class HeartbeatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    sign_in_as(@user)
    post project_switch_url(@project)
    @cto = roles(:cto)
    @developer = roles(:developer)
  end

  # --- Index ---

  test "should get index for agent with heartbeat events" do
    get role_heartbeats_url(@cto)
    assert_response :success
    assert_select "h1", "Heartbeat History"
    assert_select ".heartbeat-table"
  end

  test "should show empty state for role without events" do
    role = Role.create!(
      title: "Empty Role",
      project: @project,
      role_category: role_categories(:executor),
      adapter_type: :http,
      adapter_config: { "url" => "https://example.com" }
    )
    get role_heartbeats_url(role)
    assert_response :success
    assert_select ".heartbeats-history__empty"
  end

  test "should show trigger type badges" do
    get role_heartbeats_url(@cto)
    assert_response :success
    assert_select ".heartbeat-badge"
  end

  test "should show status indicators" do
    get role_heartbeats_url(@cto)
    assert_response :success
    assert_select ".heartbeat-status"
  end

  test "should show total event count" do
    get role_heartbeats_url(@cto)
    assert_response :success
    assert_select ".heartbeats-history__subtitle", /total events/
  end

  test "should link back to role" do
    get role_heartbeats_url(@cto)
    assert_response :success
    assert_select "a[href=?]", role_path(@cto)
  end

  test "should not show heartbeats for role from another project" do
    widgets_lead = roles(:widgets_lead)
    get role_heartbeats_url(widgets_lead)
    assert_redirected_to root_url
  end

  test "should redirect unauthenticated user" do
    sign_out
    get role_heartbeats_url(@cto)
    assert_redirected_to new_session_url
  end

  test "should redirect user without project" do
    user_without_project = User.create!(
      email_address: "heartbeatless@example.com",
      password: "password",
      password_confirmation: "password"
    )
    sign_in_as(user_without_project)
    get role_heartbeats_url(@cto)
    assert_redirected_to new_onboarding_project_url
  end

  # --- Pagination ---

  test "should handle page parameter" do
    get role_heartbeats_url(@cto, page: 1)
    assert_response :success
  end

  test "should handle invalid page gracefully" do
    get role_heartbeats_url(@cto, page: -1)
    assert_response :success
  end
end
