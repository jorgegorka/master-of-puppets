require "test_helper"
require "support/method_stub"

class Tool::McpTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:one) }

  test "all_definitions returns only the current user's exposed tools" do
    defs = Tool::Mcp.all_definitions(user: users(:one))
    names = defs.map { |d| d[:name] }
    assert_includes names, "search"
    assert_includes names, "fetch"

    # Belongs to a different user → not exposed.
    intruder = User.create!(email: "mcp-other@example.test", password: "supersecret123")
    other_server = intruder.mcp_servers.create!(slug: "other", name: "other", transport_type: :http, url: "https://example.com", status: :reachable)
    other_server.tools.create!(name: "secret", description: "hidden", input_schema: {}, discovered_at: Time.current)

    assert_not_includes Tool::Mcp.all_definitions(user: users(:one)).map { |d| d[:name] }, "secret"
  end

  test "lookup returns the tool record for the owning user" do
    assert_equal mcp_tools(:context7_search), Tool::Mcp.lookup("search", user: users(:one))
  end

  test "invoke unknown tool returns Tool::Result.failure" do
    result = Tool::Mcp.invoke(name: "nope", input: {}, user: users(:one))
    assert result.is_error
    assert_match(/unknown mcp tool/, result.error)
  end

  # The pre-fix behavior surfaced "belongs to another user", which both
  # misrouted the call and disclosed that the name existed elsewhere. The
  # secure shape: the intruder sees the same "unknown" they'd see for a typo.
  test "invoke cross-tenant returns the same failure shape as an unknown tool" do
    intruder = User.create!(email: "mcp-cross@example.test", password: "supersecret123")
    result = Tool::Mcp.invoke(name: "search", input: { query: "x" }, user: intruder)
    assert result.is_error
    assert_match(/unknown mcp tool/, result.error)
    refute_match(/belongs to another user/, result.error)
  end

  test "invoke happy path delegates to McpTool#invoke" do
    client = Object.new
    client.define_singleton_method(:call_tool) { |_n, _i| "ok-text" }
    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { client }) do
      result = Tool::Mcp.invoke(name: "search", input: { query: "x" }, user: users(:one))
      assert_not result.is_error
      assert_equal "ok-text", result.output
    end
  end
end
