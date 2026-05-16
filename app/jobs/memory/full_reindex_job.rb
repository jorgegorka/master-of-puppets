class Memory::FullReindexJob < ApplicationJob
  queue_as :default

  # Walks the memory root and syncs every `.md` file into a MemoryFile
  # row. Idempotent — `reindex!` short-circuits when the digest is
  # unchanged. Enqueued on Rails boot so out-of-band edits that occurred
  # while the supervisor or Puma were down still land in the index.
  def perform
    MemoryFile.reindex_all
  end
end
