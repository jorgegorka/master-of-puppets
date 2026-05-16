class Memory::FilesController < ApplicationController
  before_action :require_admin
  rescue_from WorkspacePath::EscapeAttempt, with: :forbid_escape

  before_action :set_file, only: %i[show update destroy]

  def show
    render :edit
  end

  def create
    path = params.require(:path)
    MemoryFile.write_at(path, params.fetch(:content, ""))
    redirect_to memory_file_path(path)
  end

  def update
    @file.write(params.require(:content))
    redirect_to memory_file_path(@file.path)
  end

  def destroy
    @file.workspace_path.to_pathname.delete
    @file.destroy
    redirect_to memory_path
  end

  private
    def set_file
      @file = MemoryFile.find_by!(path: params[:id])
    end

    def forbid_escape(error)
      render plain: "forbidden: #{error.message}", status: :forbidden
    end
end
