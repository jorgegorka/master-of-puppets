require "test_helper"

class ToolCallTest < ActiveSupport::TestCase
  test "execute raises NotImplementedError stub" do
    msg = messages(:hello)
    tc = msg.tool_calls.create!(provider_tool_id: "toolu_test", name: "read_file", source: :internal, status: :pending, input: { path: "x" })
    assert_raises(NotImplementedError) { tc.execute }
  end

  test "ordered by created_at" do
    msg = messages(:hello)
    a = msg.tool_calls.create!(provider_tool_id: "toolu_a", name: "x", source: :internal, status: :pending, input: {}, created_at: 2.minutes.ago)
    b = msg.tool_calls.create!(provider_tool_id: "toolu_b", name: "x", source: :internal, status: :pending, input: {}, created_at: 1.minute.ago)
    ordered = msg.tool_calls.ordered.to_a
    assert_operator ordered.index(a), :<, ordered.index(b)
  end
end
