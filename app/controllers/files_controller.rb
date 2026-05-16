class FilesController < ApplicationController
  before_action :require_admin

  def show
    @tree = WorkspaceFile.tree(root: ".")
  end
end
