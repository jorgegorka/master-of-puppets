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

  test "all_definitions includes the 4 built-in tools (after initializer runs)" do
    defs = Tool::Internal.all_definitions
    names = defs.map { |d| d[:name] }
    assert_includes names, "read_file"
    assert_includes names, "write_file"
    assert_includes names, "list_dir"
    assert_includes names, "run_shell"
  end

  test "register is idempotent — re-registering overwrites without duplicating" do
    before = Tool::Internal.all_definitions.length
    Tool::Internal.register("read_file", Tool::Internal::ReadFile)
    Tool::Internal.register("read_file", Tool::Internal::ReadFile)
    after = Tool::Internal.all_definitions.length
    assert_equal before, after
  end
end
