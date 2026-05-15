require "test_helper"

class ChatSessions::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "supersecret123")
    post session_path, params: { email: @user.email, password: "supersecret123" }
    @chat_session = chat_sessions(:one)
  end

  test "creates user + assistant messages and enqueues advance job" do
    assert_enqueued_with(job: Message::AdvanceJob) do
      assert_difference -> { @chat_session.messages.count }, +2 do
        post chat_session_messages_path(@chat_session), params: { content: "Hello world" }
      end
    end
    assert_response :found
  end
end
