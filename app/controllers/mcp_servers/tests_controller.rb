class McpServers::TestsController < ApplicationController
  before_action :require_admin
  include McpServerScoped

  def create
    if @mcp_server.check_reachability!
      redirect_to mcp_server_path(@mcp_server), notice: "Reachable."
    else
      redirect_to mcp_server_path(@mcp_server), alert: "Unreachable. See server details for the recorded error."
    end
  end
end
