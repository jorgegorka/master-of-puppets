module Searchable
  extend ActiveSupport::Concern

  class_methods do
    attr_reader :fts_class, :fts_foreign_key, :fts_columns

    # Declare the FTS adapter for this model. The `fts_class` should be a
    # subclass of `ContentRecord` whose `table_name` points to an `fts5`
    # virtual table; `foreign_key` is the column on that table that holds
    # the primary key of the including model. `columns:` is the ordered list
    # of column names on the FTS table populated on each write — same order
    # as the INSERT executed by `reindex_fts_entry!`.
    def searchable_via(fts_class, foreign_key:, columns:)
      @fts_class       = fts_class
      @fts_foreign_key = foreign_key
      @fts_columns     = columns
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

  # Upsert this record's FTS row. `values` must include every key listed in
  # `searchable_via columns:` — the INSERT statement is built from that list.
  def reindex_fts_entry!(**values)
    cols = self.class.fts_columns
    raise "searchable_via columns: missing on #{self.class.name}" unless cols

    fk    = self.class.fts_foreign_key
    fts   = self.class.fts_class
    table = fts.connection.quote_table_name(fts.table_name)
    conn  = fts.connection

    values  = values.symbolize_keys
    missing = cols - values.keys
    raise ArgumentError, "reindex_fts_entry! missing #{missing}" if missing.any?

    placeholders = ([ "?" ] * (cols.length + 1)).join(", ")
    conn.execute(ActiveRecord::Base.sanitize_sql([ "DELETE FROM #{table} WHERE #{fk} = ?", id ]))
    conn.execute(ActiveRecord::Base.sanitize_sql([
      "INSERT INTO #{table} (#{fk}, #{cols.join(', ')}) VALUES (#{placeholders})",
      id, *cols.map { |c| values.fetch(c) }
    ]))
  end

  # Delete this record's FTS row. Safe to call from `after_destroy_commit`.
  def clear_fts_entry!
    fts   = self.class.fts_class
    fk    = self.class.fts_foreign_key
    table = fts.connection.quote_table_name(fts.table_name)
    fts.connection.execute(ActiveRecord::Base.sanitize_sql([ "DELETE FROM #{table} WHERE #{fk} = ?", id ]))
  end
end
