require "test_helper"
require "support/method_stub"

class McpServers::TestsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "create marks server reachable when ping succeeds" do
    server = mcp_servers(:context7_http)
    server.update!(status: :unknown, last_error: "stale")
    fake_client = Object.new
    fake_client.define_singleton_method(:ping) { true }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { fake_client }) do
      post mcp_server_test_path(server)
    end

    assert_redirected_to mcp_server_path(server)
    server.reload
    assert server.reachable?
    assert_nil server.last_error
  end

  test "create marks server error and flashes alert when ping raises" do
    server = mcp_servers(:context7_http)
    failing = Object.new
    failing.define_singleton_method(:ping) { raise "boom" }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { failing }) do
      post mcp_server_test_path(server)
    end

    assert_redirected_to mcp_server_path(server)
    assert server.reload.error?
    assert_match(/boom/, server.last_error)
  end
end

class McpServers::DiscoveriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as(users(:one)) }

  test "create enqueues Mcp::DiscoveryJob" do
    server = mcp_servers(:context7_http)
    assert_enqueued_with(job: Mcp::DiscoveryJob, args: [server.id]) do
      post mcp_server_discovery_path(server)
    end
    assert_redirected_to mcp_server_path(server)
  end
end
