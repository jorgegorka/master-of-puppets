require "test_helper"

class EventableTest < ActiveSupport::TestCase
  test "track_event writes an Event row with prefixed action" do
    user = users(:one)
    Current.user = user
    assert_difference -> { Event.count }, +1 do
      user.track_event :signed_in, ip: "127.0.0.1"
    end
    event = Event.last
    assert_equal "user_signed_in", event.action
    assert_equal user, event.creator
    assert_equal user, event.eventable
    assert_equal({ "ip" => "127.0.0.1" }, event.particulars)
  end

  test "event_was_created callback runs after commit" do
    user = users(:one)
    Current.user = user
    called = false
    user.define_singleton_method(:event_was_created) { |_| called = true }
    user.track_event :touched
    assert called, "expected event_was_created hook to fire"
  end
end
