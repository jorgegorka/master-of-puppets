class Mcp::DiscoveryJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(id) { "mcp-discover:#{id}" }, on_conflict: :discard

  def perform(id)
    McpServer.find(id).discover_tools!
  end
end
