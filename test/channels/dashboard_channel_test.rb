require "test_helper"

class DashboardChannelTest < ActionCable::Channel::TestCase
  test "subscribes to the per-user dashboard stream" do
    stub_connection current_user: users(:one)
    subscribe
    assert_has_stream "dashboard:#{users(:one).id}"
  end
end
