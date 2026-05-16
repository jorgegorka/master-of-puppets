class CreateTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :terminal_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :tmux_session_name, null: false
      t.integer  :cols,              null: false, default: 120
      t.integer  :rows,              null: false, default: 40
      t.string   :cwd,               null: false
      t.integer  :status,            null: false, default: 0
      t.datetime :last_activity_at,  null: false
      t.timestamps
    end
    add_index :terminal_sessions, :tmux_session_name, unique: true
    add_index :terminal_sessions, [ :user_id, :status ]
  end
end
