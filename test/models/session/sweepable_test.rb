require "test_helper"

class Session::SweepableTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:one) }

  test "before_create defaults expires_at to DEFAULT_TTL from now" do
    s = users(:one).sessions.create!(user_agent: "ua", ip_address: "127.0.0.1")
    assert_in_delta Session::Sweepable::DEFAULT_TTL.from_now.to_i, s.expires_at.to_i, 5
  end

  test "expired? is true past expires_at" do
    s = sessions(:one).tap { |r| r.update_columns(expires_at: 1.minute.ago) }
    assert s.expired?
  end

  test "expire! sets expires_at to now and tracks :expired event" do
    s = sessions(:one)
    assert_difference -> { Event.where(action: "session_expired").count }, +1 do
      s.expire!
    end
    assert s.reload.expired?
  end

  test "touch_and_rotate_if_due! bumps last_seen_at without rotating outside window" do
    s = sessions(:one)
    s.update_columns(expires_at: Session::Sweepable::DEFAULT_TTL.from_now, last_seen_at: 1.day.ago)
    original_expires = s.expires_at
    s.touch_and_rotate_if_due!
    s.reload
    assert_operator s.last_seen_at, :>, 1.minute.ago
    assert_equal original_expires.to_i, s.expires_at.to_i
  end

  test "touch_and_rotate_if_due! extends expires_at inside rotation window" do
    s = sessions(:one)
    window = Session::Sweepable::ROTATION_WINDOW
    s.update_columns(expires_at: (window - 1.hour).from_now)
    assert_difference -> { Event.where(action: "session_rotated").count }, +1 do
      s.touch_and_rotate_if_due!
    end
    assert_operator s.reload.expires_at, :>, window.from_now
  end

  test "sweep! deletes expired rows only" do
    sessions(:one).update_columns(expires_at: 1.day.ago)
    sessions(:two).update_columns(expires_at: 1.day.from_now)
    assert_difference -> { Session.count }, -1 do
      Session.sweep!
    end
  end

  test "expired scope respects CLOCK_SKEW_MARGIN" do
    sessions(:one).update_columns(expires_at: 30.seconds.ago)
    assert_not Session.expired.include?(sessions(:one))
    sessions(:one).update_columns(expires_at: 90.seconds.ago)
    assert Session.expired.include?(sessions(:one))
  end
end
