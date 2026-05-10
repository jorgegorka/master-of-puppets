require "test_helper"

class Tasks::TimelineEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    @task = tasks(:design_homepage)

    sign_in_as(@user)
    post project_switch_url(@project)
  end

  test "responds with turbo_stream and contains target ids" do
    get task_timeline_entries_url(@task), as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match "task_timeline_entries", response.body
    assert_match "task_timeline_loader", response.body
  end

  test "respects before cursor" do
    cursor = @task.audit_events.first.created_at
    get task_timeline_entries_url(@task, before: cursor.iso8601), as: :turbo_stream
    assert_response :success
  end

  test "invalid before cursor falls through to first page" do
    get task_timeline_entries_url(@task, before: "not-a-timestamp"), as: :turbo_stream
    assert_response :success
  end

  test "redirects unauthenticated user" do
    sign_out
    get task_timeline_entries_url(@task), as: :turbo_stream
    assert_redirected_to new_session_url
  end

  test "rejects cross-project task" do
    other_task = tasks(:widgets_task)
    get task_timeline_entries_url(other_task), as: :turbo_stream
    assert_redirected_to root_url
  end
end
