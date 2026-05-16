require "test_helper"
require "support/method_stub"

class McpToolTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:one) }

  test "exposed scope returns only tools whose server is reachable" do
    assert_includes McpTool.exposed, mcp_tools(:context7_search)
    # disabled_server has no tools fixture, but if we add one it would not appear
  end

  test "lookup returns nil for unknown name" do
    assert_nil McpTool.lookup("nope")
  end

  test "lookup returns the McpTool for an exposed name" do
    assert_equal mcp_tools(:context7_search), McpTool.lookup("search")
  end

  test "invoke returns Tool::Result.ok on happy path" do
    tool   = mcp_tools(:context7_search)
    client = Object.new
    client.define_singleton_method(:call_tool) { |_name, _input| "result-text" }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { client }) do
      result = tool.invoke(input: { query: "ruby" }, user: users(:one))
      assert_not result.is_error
      assert_equal "result-text", result.output
    end
  end

  test "invoke returns Tool::Result.failure when HttpClient raises" do
    tool   = mcp_tools(:context7_search)
    client = Object.new
    client.define_singleton_method(:call_tool) { |*| raise "downstream boom" }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { client }) do
      result = tool.invoke(input: {}, user: users(:one))
      assert result.is_error
      assert_match(/downstream boom/, result.error)
    end
  end

  test "invoke enforces tenant: raises when user mismatches" do
    tool     = mcp_tools(:context7_search)
    intruder = User.create!(email: "tenant-intruder@example.test", password: "supersecret123")
    assert_raises(RuntimeError) { tool.invoke(input: {}, user: intruder) }
  end
end
