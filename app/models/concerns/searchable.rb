module Searchable
  extend ActiveSupport::Concern

  class_methods do
    attr_reader :fts_class, :fts_foreign_key

    # Declare the FTS adapter for this model. The `fts_class` should be a
    # subclass of `ContentRecord` whose `table_name` points to an `fts5`
    # virtual table; `foreign_key` is the column on that table that holds
    # the primary key of the including model.
    def searchable_via(fts_class, foreign_key:)
      @fts_class       = fts_class
      @fts_foreign_key = foreign_key
    end

    # Returns the records matching `query` in `bm25()` order.
    def matching(query)
      return [] if query.blank?
      raise "searchable_via not declared on #{self.name}" unless fts_class

      sanitized  = query.to_s.gsub('"', '""')
      table      = connection.quote_table_name(fts_class.table_name)
      ranked_ids = fts_class
        .where("#{table} MATCH ?", "\"#{sanitized}\"")
        .order(Arel.sql("bm25(#{table})"))
        .limit(50)
        .pluck(fts_foreign_key)
      return [] if ranked_ids.empty?

      rows = where(id: ranked_ids).index_by(&:id)
      ranked_ids.filter_map { |id| rows[id] }
    end
  end
end
