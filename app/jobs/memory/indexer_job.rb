class Memory::IndexerJob < ApplicationJob
  queue_as :default

  def perform(path)
    MemoryFile.reindex(path)
  end
end
