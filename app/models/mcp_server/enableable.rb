module McpServer::Enableable
  extend ActiveSupport::Concern

  def enable!
    return if reachable?
    transaction do
      update!(status: :unknown)
      track_event :enabled
    end
    Mcp::DiscoveryJob.perform_later(id)
  end

  def disable!
    return if disabled?
    transaction do
      update!(status: :disabled)
      track_event :disabled
    end
  end
end
