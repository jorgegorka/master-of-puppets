module Searchable
  extend ActiveSupport::Concern

  class_methods do
    # Returns the records matching `query` in `bm25()` order.
    #
    # Phase 2 only wires this to `MemoryFile`; the FTS adapter is hard-coded
    # to `MemoryFileFts`. Phase 3 (Skills) and beyond will lift that into a
    # `fts_adapter` declaration on each including class.
    def matching(query)
      return [] if query.blank?

      sanitized  = query.to_s.gsub('"', '""')
      ranked_ids = MemoryFileFts
        .where("memory_files_fts MATCH ?", "\"#{sanitized}\"")
        .order(Arel.sql("bm25(memory_files_fts)"))
        .limit(50)
        .pluck(:memory_file_id)
      return [] if ranked_ids.empty?

      rows = where(id: ranked_ids).index_by(&:id)
      ranked_ids.filter_map { |id| rows[id] }
    end
  end
end
