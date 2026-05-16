module McpServer::Discoverable
  extend ActiveSupport::Concern

  def discover_tools!
    raise "stdio discovery lands in Phase 4.5" if transport_stdio?

    client      = Mcp::HttpClient.new(self)
    definitions = client.list_tools

    transaction do
      tools.delete_all
      definitions.each { |d| tools.create!(d.merge(discovered_at: Time.current)) }
      update!(status: :reachable, last_checked_at: Time.current, last_error: nil)
      track_event :tools_discovered, count: definitions.size
    end
  rescue => e
    update!(status: :error, last_error: e.message.to_s[0, 255], last_checked_at: Time.current)
    track_event :discovery_failed, error: e.message.to_s[0, 255]
    raise
  end

  def discover_tools_later
    Mcp::DiscoveryJob.perform_later(id)
  end
end
