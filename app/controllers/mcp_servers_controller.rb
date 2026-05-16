class McpServersController < ApplicationController
  before_action :require_admin
  before_action :set_mcp_server, only: %i[show edit update destroy]

  def index
    @mcp_servers = Current.user.mcp_servers.order(:slug)
  end

  def show
  end

  def new
    @mcp_server = Current.user.mcp_servers.new(transport_type: :http, auth_type: :none, tool_mode: :all)
  end

  def create
    @mcp_server = Current.user.mcp_servers.new(mcp_server_params)
    if @mcp_server.save
      redirect_to mcp_server_path(@mcp_server), notice: "MCP server created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @mcp_server.update(mcp_server_params)
      redirect_to mcp_server_path(@mcp_server), notice: "MCP server updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @mcp_server.destroy
    redirect_to mcp_servers_path, notice: "MCP server removed."
  end

  private
    def set_mcp_server
      @mcp_server = Current.user.mcp_servers.find(params[:id])
    end

    def mcp_server_params
      params.require(:mcp_server).permit(
        :slug, :name, :transport_type, :url, :command_template,
        :auth_type, :auth_payload, :env_payload, :tool_mode
      )
    end
end
