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

  test "dashboard incidents are scoped to the current user — does not leak across tenants" do
    # Seed: an incident on a chat owned by users(:member), creator nil.
    other_chat = users(:member).chat_sessions.create!(
      title: "other", model: "claude-haiku-4-5", provider: "anthropic"
    )
    other_chat.events.create!(action: "leaked_message_failed", creator: nil, occurred_at: 1.minute.ago)

    sign_in_as users(:one)
    get root_path
    assert_response :success
    # users(:one) shouldn't see :member's incident
    assert_no_match(/leaked_message_failed/, response.body)
  end
end
