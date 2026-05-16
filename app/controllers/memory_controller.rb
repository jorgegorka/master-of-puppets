class MemoryController < ApplicationController
  before_action :require_admin

  def show
    @files = MemoryFile.recently_changed.limit(20)
    @tree  = WorkspaceFile.tree(root: "memory")
  end
end
