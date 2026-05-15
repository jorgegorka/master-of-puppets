class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :chat_session, null: false, foreign_key: true
      t.integer :role, null: false
      t.json    :content_blocks
      t.json    :stream_cursor
      t.integer :status, null: false, default: 0
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :cache_read_tokens
      t.integer :cache_creation_tokens
      t.decimal :cost_usd, precision: 12, scale: 6
      t.string  :model
      t.string  :provider
      t.text    :error_message

      t.timestamps
    end
    add_index :messages, [ :chat_session_id, :created_at ]
  end
end
