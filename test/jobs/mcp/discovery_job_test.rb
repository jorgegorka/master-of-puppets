require "test_helper"
require "support/method_stub"

class Mcp::DiscoveryJobTest < ActiveJob::TestCase
  setup { Current.session = sessions(:one) }

  test "perform calls discover_tools! on the deserialized server" do
    server = mcp_servers(:context7_http)
    called = false
    with_singleton_method(server, :discover_tools!, -> { called = true }) do
      # ActiveJob deserializes via GlobalID into a fresh AR instance — pass
      # the instance directly here to match the perform signature without
      # round-tripping through the queue.
      Mcp::DiscoveryJob.new.perform(server)
    end
    assert called, "expected perform(server) to call discover_tools! on the passed-in record"
  end

  test "deleted server between enqueue and perform is silently discarded" do
    server = users(:one).mcp_servers.create!(slug: "tmp", name: "Tmp", transport_type: :http, url: "https://example.com")
    # Enqueue with the live record (so GlobalID serializes a valid id), then
    # destroy the row so deserialize raises ActiveJob::DeserializationError.
    Mcp::DiscoveryJob.perform_later(server)
    server.destroy
    assert_nothing_raised do
      perform_enqueued_jobs(only: Mcp::DiscoveryJob)
    end
  end
end
