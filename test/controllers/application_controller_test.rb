require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "expired session redirects to sign-in with flash and records the expired event" do
    sign_in_as(users(:one))
    session = users(:one).sessions.last
    session.update_columns(expires_at: 1.minute.ago)

    assert_difference -> { Event.where(action: "session_expired").count }, +1 do
      get root_path
    end

    assert_redirected_to new_session_path
    assert_equal "Session expired. Please sign in again.", flash[:alert]
    # session.expire! preserves the row (and its event trail) until the
    # next sweep; the row should be marked expired, not destroyed.
    session.reload
    assert_operator session.expires_at, :<=, Time.current
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
