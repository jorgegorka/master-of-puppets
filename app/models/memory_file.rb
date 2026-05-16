class MemoryFile < ApplicationRecord
  include Eventable
  include Searchable

  validates :path, presence: true, uniqueness: true

  scope :recently_changed, -> { order(disk_mtime: :desc) }

  def workspace_path
    WorkspacePath.resolve(root: "memory", raw: path)
  end

  def body
    workspace_path.read
  end
end
