require "test_helper"

class EventIncidentsTest < ActiveSupport::TestCase
  test "incidents includes error_ events and excludes :reloaded with creator nil" do
    msg = messages(:hello)
    msg.events.create!(action: "message_failed",    creator: users(:one), occurred_at: 1.hour.ago)
    msg.events.create!(action: "message_streamed",  creator: users(:one), occurred_at: 1.hour.ago)
    msg.events.create!(action: "skill_reloaded",    creator: nil,         occurred_at: 1.hour.ago)
    msg.events.create!(action: "tool_call_errored", creator: nil,         occurred_at: 1.hour.ago)

    actions = Event.incidents.pluck(:action)
    assert_includes actions, "message_failed"
    assert_includes actions, "tool_call_errored"
    assert_not_includes actions, "message_streamed"
    assert_not_includes actions, "skill_reloaded"
  end
end
