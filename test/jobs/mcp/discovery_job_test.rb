require "test_helper"
require "support/method_stub"

class Mcp::DiscoveryJobTest < ActiveJob::TestCase
  setup { Current.session = sessions(:one) }

  test "perform looks up the server and calls discover_tools!" do
    server = mcp_servers(:context7_http)
    called = false
    with_singleton_method(McpServer, :find, ->(id) { server.tap { called = (id == server.id) } }) do
      with_singleton_method(server, :discover_tools!, -> { true }) do
        Mcp::DiscoveryJob.new.perform(server.id)
      end
    end
    assert called, "expected McpServer.find to be called with the job's id"
  end
end
