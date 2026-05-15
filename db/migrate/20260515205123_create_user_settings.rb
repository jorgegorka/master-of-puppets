class CreateUserSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :user_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string  :theme,                 null: false, default: "claude-official"
      t.string  :accent,                null: false, default: "indigo"
      t.integer :editor_font_size,      null: false, default: 13
      t.boolean :sidebar_collapsed,     null: false, default: false
      t.boolean :notifications_enabled, null: false, default: true
      t.integer :usage_threshold,       null: false, default: 80

      t.timestamps
    end
  end
end
