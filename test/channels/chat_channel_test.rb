require "test_helper"

class ChatChannelTest < ActionCable::Channel::TestCase
  test "subscribes a user to their own session" do
    stub_connection current_user: users(:one)
    subscribe chat_session_id: chat_sessions(:one).id
    assert subscription.confirmed?
    assert_has_stream_for chat_sessions(:one)
  end

  test "refuses subscription for someone else's session" do
    other = User.create!(email: "intruder@x.com", password: "supersecret123")
    stub_connection current_user: other
    assert_raises(ActiveRecord::RecordNotFound) do
      subscribe chat_session_id: chat_sessions(:one).id
    end
  end
end
