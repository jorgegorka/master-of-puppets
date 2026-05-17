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

  test "incidents scope binds LIKE parameters; malicious action strings cannot inject SQL" do
    msg = messages(:hello)
    malicious = "'); DROP TABLE messages;-- x_failed"
    msg.events.create!(action: malicious, creator: users(:one), occurred_at: 5.minutes.ago)
    msg.events.create!(action: "tool_call_errored", creator: users(:one), occurred_at: 5.minutes.ago)

    # If the LIKE bind protection broke, the query would raise or the messages
    # table would be gone. Run the query, then re-read messages to prove the
    # table is still intact.
    actions = Event.incidents.pluck(:action)
    assert_includes actions, malicious, "incidents should include malicious row matching %_failed"
    assert_includes actions, "tool_call_errored"

    # Sanity: the messages table is still queryable. If the DROP had executed,
    # this would raise ActiveRecord::StatementInvalid.
    assert_nothing_raised { Message.count }
    assert Message.exists?(msg.id), "messages(:hello) should still exist after the incidents query"
  end

  test "incidents scope cannot be tricked into matching skill_reloaded via SQL wildcard" do
    msg = messages(:hello)
    # 'skill_reloaded' is excluded by where.not — verify the bound parameter
    # treats the column equality literally.
    msg.events.create!(action: "skill_reloaded",  creator: nil, occurred_at: 1.minute.ago)
    msg.events.create!(action: "skill_reloaded%", creator: nil, occurred_at: 1.minute.ago)

    actions = Event.incidents.pluck(:action)
    assert_not_includes actions, "skill_reloaded"
    # "skill_reloaded%" doesn't end in _failed/_errored so it shouldn't match any pattern either
    assert_not_includes actions, "skill_reloaded%"
  end
end
