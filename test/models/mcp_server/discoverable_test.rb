require "test_helper"
require "support/method_stub"

class McpServer::DiscoverableTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:one) }

  test "discover_tools! replaces existing tools and flips status to :reachable" do
    server = mcp_servers(:context7_http)
    server.update!(status: :unknown, last_error: "stale error")

    fake_client = Object.new
    fake_client.define_singleton_method(:list_tools) do
      [
        { name: "echo",  description: "echo back",  input_schema: { "type" => "object" } },
        { name: "ping",  description: "pong",       input_schema: {} }
      ]
    end

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { fake_client }) do
      assert_difference -> { server.tools.count }, +2 - server.tools.count do
        server.discover_tools!
      end
    end

    server.reload
    assert server.reachable?
    assert_nil server.last_error
    assert_equal %w[echo ping], server.tools.order(:name).pluck(:name)
  end

  test "discover_tools! on failure flips status to :error and re-raises" do
    server = mcp_servers(:context7_http)
    failing_client = Object.new
    failing_client.define_singleton_method(:list_tools) { raise "boom" }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { failing_client }) do
      assert_raises(RuntimeError) { server.discover_tools! }
    end

    server.reload
    assert server.error?
    assert_match(/boom/, server.last_error)
  end

  test "stdio discovery raises until Phase 4.5" do
    server = mcp_servers(:stdio_only)
    assert_raises(RuntimeError) { server.discover_tools! }
  end
end
