require "test_helper"

class ChatSessionTest < ActiveSupport::TestCase
  test "active scope excludes archived" do
    session = chat_sessions(:one)
    session.archive
    refute_includes ChatSession.active, session
  end

  test "archive then unarchive flips state and tracks events" do
    session = chat_sessions(:one)
    refute session.archived?
    assert_difference -> { Event.where(action: "chat_session_archived").count }, +1 do
      session.archive
    end
    assert session.reload.archived?
    assert_difference -> { Event.where(action: "chat_session_unarchived").count }, +1 do
      session.unarchive
    end
    refute session.reload.archived?
  end

  test "pin then unpin flips state" do
    session = chat_sessions(:one)
    refute session.pinned?
    session.pin
    assert session.reload.pinned?
    session.unpin
    refute session.reload.pinned?
  end

  test "fork copies messages up through cursor and references parent" do
    session = chat_sessions(:one)
    session.messages.create!(role: :assistant, content_blocks: [ { type: "text", text: "Hi" } ], status: :completed, model: "claude-opus-4-7", provider: "anthropic")
    cursor = session.messages.ordered.last
    child = session.fork(at: cursor)
    assert_equal session.messages.count, child.messages.count
    assert_equal session, child.forked_from
    assert child.title.end_with?("(fork)")
  end
end
