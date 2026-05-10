require "test_helper"

class Roles::TimelineEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    @role = roles(:cto)

    sign_in_as(@user)
    post project_switch_url(@project)
  end

  test "responds with turbo_stream and contains target ids" do
    get role_timeline_entries_url(@role), as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match "role_timeline_entries", response.body
    assert_match "role_timeline_loader", response.body
  end

  test "respects before cursor" do
    cursor = 1.minute.from_now
    get role_timeline_entries_url(@role, before: cursor.iso8601), as: :turbo_stream
    assert_response :success
  end

  test "invalid before cursor falls through to first page" do
    get role_timeline_entries_url(@role, before: "not-a-timestamp"), as: :turbo_stream
    assert_response :success
  end

  test "redirects unauthenticated user" do
    sign_out
    get role_timeline_entries_url(@role), as: :turbo_stream
    assert_redirected_to new_session_url
  end

  test "rejects cross-project role" do
    other_role = roles(:widgets_lead)
    get role_timeline_entries_url(other_role), as: :turbo_stream
    assert_redirected_to root_url
  end
end
