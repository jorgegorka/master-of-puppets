module McpServerScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_mcp_server
  end

  private

  def set_mcp_server
    @mcp_server = Current.user.mcp_servers.find(params[:mcp_server_id] || params[:id])
  end
end
