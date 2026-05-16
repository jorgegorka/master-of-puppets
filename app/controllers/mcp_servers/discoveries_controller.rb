class McpServers::DiscoveriesController < ApplicationController
  before_action :require_admin

  def create
    server = Current.user.mcp_servers.find(params[:mcp_server_id])
    Mcp::DiscoveryJob.perform_later(server.id)
    redirect_to mcp_server_path(server), notice: "Discovery queued."
  end
end
