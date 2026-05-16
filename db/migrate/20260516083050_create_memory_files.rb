class CreateMemoryFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :memory_files do |t|
      t.string   :path,           null: false
      t.string   :title
      t.json     :tags,           default: []
      t.string   :content_digest, null: false
      t.integer  :byte_size,      null: false
      t.datetime :disk_mtime,     null: false
      t.timestamps
    end
    add_index :memory_files, :path, unique: true
    add_index :memory_files, :disk_mtime
  end
end
