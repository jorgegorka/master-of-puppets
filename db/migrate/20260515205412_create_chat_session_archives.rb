class CreateChatSessionArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_session_archives do |t|
      t.references :chat_session, null: false, foreign_key: true, index: { unique: true }
      t.references :user,         null: false, foreign_key: true

      t.timestamps
    end
  end
end
