class McpServers::TestsController < ApplicationController
  before_action :require_admin

  def create
    server = Current.user.mcp_servers.find(params[:mcp_server_id])
    Mcp::HttpClient.new(server).ping
    server.update!(status: :reachable, last_error: nil, last_checked_at: Time.current)
    redirect_to mcp_server_path(server), notice: "Reachable."
  rescue => e
    # Raw Faraday / SSRF / auth messages can carry resolved IPs, internal
    # hostnames, or credentials — never echo them to the browser. The detail
    # is persisted to last_error for the admin to inspect on the server page
    # and logged server-side; the flash stays generic.
    Rails.logger.warn("[mcp_servers/tests] ping failed: #{e.class}: #{e.message}")
    server&.update!(status: :error, last_error: e.message.to_s[0, 255], last_checked_at: Time.current)
    redirect_to mcp_server_path(server), alert: "Unreachable. See server details for the recorded error."
  end
end
