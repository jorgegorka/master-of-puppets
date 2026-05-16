class McpServers::TestsController < ApplicationController
  before_action :require_admin

  def create
    server = Current.user.mcp_servers.find(params[:mcp_server_id])
    Mcp::HttpClient.new(server).ping
    server.update!(status: :reachable, last_error: nil, last_checked_at: Time.current)
    redirect_to mcp_server_path(server), notice: "Reachable."
  rescue => e
    server&.update!(status: :error, last_error: e.message.to_s[0, 255], last_checked_at: Time.current)
    redirect_to mcp_server_path(server), alert: "Unreachable: #{e.message}"
  end
end
