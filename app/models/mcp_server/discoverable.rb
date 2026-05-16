module McpServer::Discoverable
  extend ActiveSupport::Concern

  def discover_tools!
    raise "stdio discovery lands in Phase 4.5" if transport_stdio?

    client      = Mcp::HttpClient.new(self)
    definitions = client.list_tools

    transaction do
      # lock! serializes parallel discoveries to the same server. The
      # DiscoveryJob's limits_concurrency already ensures one queued job per
      # server, but a manual discover_tools! invocation could still race; this
      # is defense-in-depth.
      lock!
      reconcile_tools!(definitions)
      update!(status: :reachable, last_checked_at: Time.current, last_error: nil)
      track_event :tools_discovered, count: definitions.size
    end
  rescue StandardError => e
    # Status flip + audit event are one logical state change; the rescue
    # arm must be atomic for the same reason the happy path is.
    transaction do
      update!(status: :error, last_error: e.message.to_s[0, 255], last_checked_at: Time.current)
      track_event :discovery_failed, error: e.message.to_s[0, 255]
    end
    raise
  end

  def discover_tools_later
    Mcp::DiscoveryJob.perform_later(self)
  end

  private

  # Upsert by (mcp_server_id, name) and only delete tools that fell off the
  # latest list — the previous `delete_all + create!` produced a gap during
  # which a concurrent Tool::Mcp.invoke would see an empty join and 404
  # every tool of a fully-reachable server. Now valid tools are continuously
  # present; only the actually-removed ones disappear at the end.
  def reconcile_tools!(definitions)
    now = Time.current
    definitions.each do |d|
      tool = tools.find_or_initialize_by(name: d[:name])
      tool.assign_attributes(
        description: d[:description],
        input_schema: d[:input_schema],
        discovered_at: now
      )
      tool.save!
    end
    incoming = definitions.map { |d| d[:name] }
    if incoming.any?
      tools.where.not(name: incoming).delete_all
    else
      tools.delete_all
    end
  end
end
