class AddCreatedAtIndexToMessages < ActiveRecord::Migration[8.1]
  def change
    add_index :messages, :created_at, name: "index_messages_on_created_at"
  end
end
