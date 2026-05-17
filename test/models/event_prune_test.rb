require "test_helper"

class EventPruneTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "prune! deletes :info events older than 90 days; keeps failures up to 365 days" do
    msg = messages(:hello)
    old_info  = msg.events.create!(action: "skill_installed",      creator: users(:one), occurred_at: 100.days.ago)
    keep_info = msg.events.create!(action: "skill_installed",      creator: users(:one), occurred_at: 30.days.ago)
    old_fail  = msg.events.create!(action: "skill_install_failed", creator: users(:one), occurred_at: 400.days.ago)
    keep_fail = msg.events.create!(action: "skill_install_failed", creator: users(:one), occurred_at: 200.days.ago)

    assert_difference -> { Event.count }, -2 do
      Event.prune!
    end
    refute Event.exists?(id: old_info.id)
    refute Event.exists?(id: old_fail.id)
    assert Event.exists?(id: keep_info.id)
    assert Event.exists?(id: keep_fail.id)
  end
end
