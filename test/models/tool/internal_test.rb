require "test_helper"

class Tool::InternalTest < ActiveSupport::TestCase
  # Snapshot the registry so tests that mutate it (register a fake tool, etc.)
  # don't leak state into sibling tests.
  setup do
    @registry_snapshot = Tool::Internal.send(:registry).dup
  end

  teardown do
    Tool::Internal.instance_variable_set(:@registry, @registry_snapshot)
  end

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

  test "invoke returns Tool::Result.failure for missing name" do
    result = Tool::Internal.invoke(name: "missing_xyz_#{SecureRandom.hex(4)}", input: {}, user: users(:one))
    assert result.is_error
    assert_match(/unknown tool/, result.error)
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

  test "invoke with missing required key returns Result.failure" do
    result = Tool::Internal.invoke(name: "read_file", input: {}, user: users(:one))
    assert result.is_error
    assert_match(/invalid input/, result.error)
    assert_match(/path/, result.error)
  end

  test "invoke with wrong-typed key returns Result.failure" do
    result = Tool::Internal.invoke(name: "read_file", input: { "path" => 123 }, user: users(:one))
    assert result.is_error
    assert_match(/invalid input/, result.error)
    assert_match(/string/, result.error)
  end

  test "validation_error accepts well-formed input" do
    schema = { type: "object", properties: { path: { type: "string" } }, required: [ "path" ] }
    assert_nil Tool::Internal.validation_error({ "path" => "ok.md" }, schema)
  end

  test "validation_error reports the missing key" do
    schema = { type: "object", properties: { path: { type: "string" } }, required: [ "path" ] }
    assert_match(/path/, Tool::Internal.validation_error({}, schema))
  end

  test "Tool::Internal does not define Forbidden any more (T8)" do
    refute defined?(Tool::Internal::Forbidden), "Forbidden was never referenced — should be deleted"
  end

  test "Tool::Internal does not define UnknownTool any more (T9)" do
    refute defined?(Tool::Internal::UnknownTool), "UnknownTool replaced by Tool::Result.failure"
  end
end
