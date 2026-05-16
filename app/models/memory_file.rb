class MemoryFile < ApplicationRecord
  include Eventable
  include Searchable
  include Reindexable

  validates :path, presence: true, uniqueness: true

  scope :recently_changed, -> { order(disk_mtime: :desc) }

  def self.reindex_later(path)
    Memory::IndexerJob.perform_later(path)
  end

  def workspace_path
    WorkspacePath.resolve(root: "memory", raw: path)
  end

  def body
    workspace_path.read
  end
end
