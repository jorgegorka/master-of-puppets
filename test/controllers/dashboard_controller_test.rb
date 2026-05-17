require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include ControllerSignInHelpers

  test "GET /dashboard renders rollups, incidents, mcp servers, runs" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select "[data-controller~='chart']"   # at least one chart container
    assert_select "section.incidents"
    assert_select "section.mcp-status"
    assert_select "section.recent-runs"
  end

  test "dashboard scopes data to current user" do
    sign_in_as users(:member)
    get root_path
    assert_response :success
    assert_select "section.recent-runs li", false
  end
end
