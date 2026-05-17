class MemoryFile < ApplicationRecord
  include Eventable
  include Searchable
  searchable_via MemoryFileFts, foreign_key: :memory_file_id,
                 columns: %i[path title tags body]

  include Reindexable
  include Writable

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
