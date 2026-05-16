class Mcp::DiscoveryJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(server) { "mcp-discover:#{server.id}" }, on_conflict: :discard

  def perform(server)
    server.discover_tools!
  end
end
