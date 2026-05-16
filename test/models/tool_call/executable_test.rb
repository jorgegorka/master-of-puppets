require "test_helper"

class ToolCall::ExecutableTest < ActiveSupport::TestCase
  setup do
    @msg = messages(:hello)
    @tc  = ToolCall.create!(
      message: @msg,
      provider_tool_id: "toolu_test",
      name: "read_file",
      source: :internal,
      input: { "path" => "memory/MEMORY.md" },
      status: :pending
    )
    Tool::Internal.stub :invoke, Tool::Result.ok("body") do
      @tc.execute
    end
  end

  test "moves pending → succeeded + persists output" do
    assert @tc.reload.succeeded?
    assert_equal "body", @tc.output["content"]
    assert_not_nil @tc.started_at
    assert_not_nil @tc.finished_at
  end

  test "tracks invoked + succeeded events" do
    events = @tc.events.pluck(:action)
    assert_includes events, "tool_call_invoked"
    assert_includes events, "tool_call_succeeded"
  end

  test "re-executing a non-pending call raises but does NOT overwrite status" do
    assert @tc.reload.succeeded?, "preconditions: setup left tc :succeeded"
    assert_raises(RuntimeError) { @tc.execute }
    assert @tc.reload.succeeded?, "the pending? guard must NOT flip a succeeded row to :failed"
    assert_equal "body", @tc.output["content"], "output payload must remain intact"
  end

  test "failed Tool::Result transitions to failed + records error_message" do
    tc = ToolCall.create!(message: @msg, provider_tool_id: "toolu_bad", name: "read_file",
      source: :internal, input: { "path" => "missing" }, status: :pending)
    Tool::Internal.stub :invoke, Tool::Result.failure("not found") do
      tc.execute
    end
    assert tc.reload.failed?
    assert_equal "not found", tc.error_message
  end

  test "mcp and skill sources return Phase-4/6 placeholder failure (don't raise)" do
    tc = ToolCall.create!(message: @msg, provider_tool_id: "toolu_mcp", name: "do_x",
      source: :mcp, input: {}, status: :pending)
    tc.execute
    assert tc.reload.failed?
    assert_match /Phase 4/, tc.error_message
  end

  test ":unknown source returns a clean Tool::Result.failure (does not raise)" do
    tc = ToolCall.create!(message: @msg, provider_tool_id: "toolu_unk", name: "garbage",
      source: :unknown, input: {}, status: :pending)
    tc.execute
    assert tc.reload.failed?
    assert_match(/unknown tool: garbage/, tc.error_message)
  end
end
