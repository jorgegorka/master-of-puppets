require "test_helper"

class McpServerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { Current.session = sessions(:one) }

  test "validations enforce slug uniqueness per user" do
    dupe = users(:one).mcp_servers.new(
      slug: "context7",
      name: "Dupe",
      transport_type: :http,
      url: "https://example.com"
    )
    assert_not dupe.valid?
    assert_includes dupe.errors[:slug], "has already been taken"
  end

  test "http transport requires url" do
    s = users(:one).mcp_servers.new(slug: "x", name: "x", transport_type: :http)
    assert_not s.valid?
    assert_includes s.errors[:url], "can't be blank"
  end

  test "stdio transport requires command_template" do
    s = users(:one).mcp_servers.new(slug: "stx", name: "x", transport_type: :stdio)
    assert_not s.valid?
    assert_includes s.errors[:command_template], "can't be blank"
  end

  test "enum members are available" do
    assert_equal %w[http sse stdio], McpServer.transport_types.keys
    assert_equal %w[none bearer basic], McpServer.auth_types.keys
    assert_equal %w[unknown reachable error disabled], McpServer.statuses.keys
  end

  test "disable! transitions reachable → disabled and tracks event" do
    server = mcp_servers(:context7_http)
    assert_difference -> { Event.where(action: "mcp_server_disabled").count }, +1 do
      server.disable!
    end
    assert server.reload.disabled?
  end

  test "enable! from disabled queues a discovery" do
    server = mcp_servers(:disabled_server)
    assert_difference -> { Event.where(action: "mcp_server_enabled").count }, +1 do
      assert_enqueued_with(job: Mcp::DiscoveryJob, args: [server.id]) do
        server.enable!
      end
    end
    assert_equal "unknown", server.reload.status
  end

  test "enable! is a no-op on already-reachable servers" do
    server = mcp_servers(:context7_http)
    assert_no_difference -> { Event.where(action: "mcp_server_enabled").count } do
      assert_no_enqueued_jobs only: Mcp::DiscoveryJob do
        server.enable!
      end
    end
  end
end
