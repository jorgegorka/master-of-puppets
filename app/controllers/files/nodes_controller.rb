class Files::NodesController < ApplicationController
  before_action :require_admin
  rescue_from WorkspacePath::EscapeAttempt, with: :forbid_escape
  rescue_from Errno::ENOENT, with: :not_found

  before_action :resolve_path

  def index
    render json: WorkspaceFile.tree(root: @rel)
  end

  def show
    if @wsp.to_pathname.directory?
      @tree = WorkspaceFile.tree(root: @rel)
      render :index
    else
      @body = @wsp.read
      render :show
    end
  end

  def create
    FileUtils.mkdir_p(@wsp.absolute.dirname)
    File.write(@wsp.absolute, params.fetch(:content, ""))
    redirect_to files_node_path(@rel)
  end

  def update
    File.write(@wsp.absolute, params.require(:content))
    redirect_to files_node_path(@rel)
  end

  def destroy
    if @wsp.to_pathname.directory?
      FileUtils.rm_rf(@wsp.absolute)
    else
      @wsp.absolute.delete
    end
    redirect_to files_path
  end

  private
    def resolve_path
      @rel = params[:id].presence || "."
      @wsp = WorkspacePath.resolve(root: ".", raw: @rel)
    end

    def forbid_escape(error)
      render plain: "forbidden: #{error.message}", status: :forbidden
    end

    def not_found(_error)
      render plain: "not found", status: :not_found
    end
end
