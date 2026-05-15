require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "content_blocks defaults to empty array" do
    msg = chat_sessions(:one).messages.new(role: :user, status: :pending)
    msg.valid?
    assert_equal [], msg.content_blocks
  end

  test "advance! raises NotImplementedError stub" do
    msg = messages(:hello)
    assert_raises(NotImplementedError) { msg.advance! }
  end

  test "ordered scope sorts by created_at" do
    session = chat_sessions(:one)
    a = session.messages.create!(role: :user, status: :completed, content_blocks: [], model: "m", provider: "p", created_at: 2.minutes.ago)
    b = session.messages.create!(role: :user, status: :completed, content_blocks: [], model: "m", provider: "p", created_at: 1.minute.ago)
    ordered = session.messages.ordered.to_a
    assert_operator ordered.index(a), :<, ordered.index(b)
  end
end
