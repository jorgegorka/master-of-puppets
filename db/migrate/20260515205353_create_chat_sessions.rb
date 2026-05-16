class CreateChatSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :title,    null: false
      t.string  :model,    null: false
      t.string  :provider, null: false
      t.references :forked_from, null: true, foreign_key: { to_table: :chat_sessions }
      t.string :share_token
      t.datetime :last_active_at

      t.timestamps
    end
    add_index :chat_sessions, :share_token, unique: true, where: "share_token IS NOT NULL"
  end
end
