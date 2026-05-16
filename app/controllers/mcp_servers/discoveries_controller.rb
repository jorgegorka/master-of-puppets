class McpServers::DiscoveriesController < ApplicationController
  before_action :require_admin
  include McpServerScoped

  def create
    @mcp_server.discover_tools_later
    redirect_to mcp_server_path(@mcp_server), notice: "Discovery queued."
  end
end
