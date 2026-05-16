class CreateMemoryFilesFts < ActiveRecord::Migration[8.1]
  COLUMNS = [
    "memory_file_id UNINDEXED",
    "path",
    "title",
    "tags",
    "body",
    "tokenize = 'porter'"
  ].freeze

  def change
    create_virtual_table :memory_files_fts, :fts5, COLUMNS
  end
end
