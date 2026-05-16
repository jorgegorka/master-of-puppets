require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "expired session redirects to sign-in with flash" do
    sign_in_as(users(:one))
    session = users(:one).sessions.last
    session.update_columns(expires_at: 1.minute.ago)

    get root_path

    assert_redirected_to new_session_path
    assert_equal "Session expired. Please sign in again.", flash[:alert]
    assert_not Session.exists?(session.id), "expired session row should be destroyed on detection"
  end

  test "valid session bumps last_seen_at on each request" do
    sign_in_as(users(:one))
    session = users(:one).sessions.last
    session.update_columns(last_seen_at: 1.day.ago, expires_at: 1.year.from_now)

    get root_path

    assert_response :success
    assert_operator session.reload.last_seen_at, :>, 1.minute.ago
  end
end
