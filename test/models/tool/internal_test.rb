require "test_helper"

class Tool::InternalTest < ActiveSupport::TestCase
  test "register + lookup round-trip" do
    fake = Class.new(Tool::Internal) do
      def self.tool_name;    "test_tool"; end
      def self.description;  "Test tool"; end
      def self.input_schema; { type: "object" }; end
      def self.invoke(input:, user:); Tool::Result.ok("ok"); end
    end
    Tool::Internal.register("test_tool", fake)
    assert_equal fake, Tool::Internal.lookup("test_tool")
  end

  test "lookup returns nil for unknown" do
    assert_nil Tool::Internal.lookup("nonexistent_xyz_#{SecureRandom.hex(4)}")
  end

  test "invoke raises UnknownTool for missing name" do
    assert_raises(Tool::Internal::UnknownTool) do
      Tool::Internal.invoke(name: "missing_xyz_#{SecureRandom.hex(4)}", input: {}, user: users(:one))
    end
  end

  test "Tool::Result.ok and .failure produce correct shape" do
    ok = Tool::Result.ok("hello")
    assert_equal "hello", ok.output
    refute ok.is_error

    bad = Tool::Result.failure("oops")
    assert_equal "oops", bad.error
    assert bad.is_error
  end

  test "Tool::Result#to_tool_block returns Anthropic-shaped hash" do
    block = Tool::Result.ok("body").to_tool_block("toolu_x")
    assert_equal "tool_result", block["type"]
    assert_equal "toolu_x", block["tool_use_id"]
    assert_equal "body", block["content"]
    refute block["is_error"]
  end
end
