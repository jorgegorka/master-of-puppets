class CreateToolCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_calls do |t|
      t.references :message, null: false, foreign_key: true
      t.string  :provider_tool_id, null: false
      t.string  :name, null: false
      t.integer :source, null: false
      t.json    :input
      t.json    :output
      t.integer :status, null: false, default: 0
      t.text    :error_message
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :tool_calls, [ :message_id, :provider_tool_id ], unique: true
  end
end
