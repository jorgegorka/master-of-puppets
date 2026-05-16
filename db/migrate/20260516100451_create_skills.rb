class CreateSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skills do |t|
      t.string  :slug,           null: false
      t.string  :name,           null: false
      t.string  :category,       null: false
      t.text    :description
      t.json    :manifest,       null: false, default: {}
      t.string  :source_path,    null: false
      t.integer :origin,         null: false, default: 0
      t.integer :security_level, null: false, default: 0
      t.string  :body_digest,    null: false
      t.datetime :discovered_at, null: false

      t.timestamps
    end
    add_index :skills, :slug,     unique: true
    add_index :skills, :category
    add_index :skills, :security_level
  end
end
