class AddPrefixToFtsTables < ActiveRecord::Migration[8.1]
  SKILLS_COLS  = "skill_id UNINDEXED, slug, name, category, description, body".freeze
  MEMORY_COLS  = "memory_file_id UNINDEXED, path, title, tags, body".freeze

  def up
    rebuild("skills_fts", SKILLS_COLS, key: "skill_id")
    rebuild("memory_files_fts", MEMORY_COLS, key: "memory_file_id")
  end

  def down
    rebuild("skills_fts", SKILLS_COLS, key: "skill_id", with_prefix: false)
    rebuild("memory_files_fts", MEMORY_COLS, key: "memory_file_id", with_prefix: false)
  end

  private
    # The CREATE VIRTUAL TABLE statement is intentionally kept on a single
    # line. Rails' SQLite schema dumper parses the stored CREATE SQL with the
    # regex /USING\s+(\w+)\s*\((.*)\)/i (no multiline flag) — a multi-line
    # statement causes schema:dump to crash with NoMethodError on nil#split.
    def rebuild(table, cols, key:, with_prefix: true)
      cols_no_unindexed = cols.gsub(" UNINDEXED", "")
      plain_keys        = cols_no_unindexed.split(", ").map(&:strip).join(", ")
      prefix_clause     = with_prefix ? ", prefix='2 3'" : ""
      execute "ALTER TABLE #{table} RENAME TO #{table}_old"
      execute "CREATE VIRTUAL TABLE #{table} USING fts5(#{cols}, tokenize = 'porter'#{prefix_clause})"
      execute "INSERT INTO #{table} (#{plain_keys}) SELECT #{plain_keys} FROM #{table}_old"
      execute "DROP TABLE #{table}_old"
    end
end
