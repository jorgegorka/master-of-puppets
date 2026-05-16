require "test_helper"
require "support/method_stub"

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
      assert_enqueued_with(job: Mcp::DiscoveryJob, args: [server]) do
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

  test "check_reachability! flips status to :reachable and tracks ok event on ping success" do
    server = mcp_servers(:context7_http)
    server.update!(status: :unknown, last_error: "stale")
    fake_client = Object.new
    fake_client.define_singleton_method(:ping) { true }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { fake_client }) do
      assert_difference -> { Event.where(action: "mcp_server_reachability_checked").count }, +1 do
        assert_equal true, server.check_reachability!
      end
    end
    server.reload
    assert server.reachable?
    assert_nil server.last_error
    assert_not_nil server.last_checked_at
  end

  test "check_reachability! flips status to :error and stores truncated last_error on ping failure" do
    server = mcp_servers(:context7_http)
    failing = Object.new
    failing.define_singleton_method(:ping) { raise "boom: 10.0.0.5 connection refused" }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { failing }) do
      assert_difference -> { Event.where(action: "mcp_server_reachability_checked").count }, +1 do
        assert_equal false, server.check_reachability!
      end
    end
    server.reload
    assert server.error?
    assert_match(/boom/, server.last_error)
  end

  test "check_reachability! does not raise — controllers rely on the return value" do
    server = mcp_servers(:context7_http)
    failing = Object.new
    failing.define_singleton_method(:ping) { raise "downstream boom" }

    with_singleton_method(Mcp::HttpClient, :new, ->(_s) { failing }) do
      assert_nothing_raised { server.check_reachability! }
    end
  end
end
