require "test_helper"

class SkillsChannelTest < ActionCable::Channel::TestCase
  test "subscribes to the 'skills' stream" do
    subscribe
    assert subscription.confirmed?
    assert_has_stream "skills"
  end
end
