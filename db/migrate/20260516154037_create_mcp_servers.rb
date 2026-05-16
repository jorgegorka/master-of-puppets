class CreateMcpServers < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_servers do |t|
      t.references :user,            null: false, foreign_key: true
      t.string  :slug,               null: false
      t.string  :name,               null: false
      t.integer :transport_type,     null: false, default: 0
      t.string  :url
      t.string  :command_template
      t.text    :env_payload
      t.integer :auth_type,          null: false, default: 0
      t.text    :auth_payload
      t.integer :tool_mode,          null: false, default: 0
      t.json    :tool_list,          default: []
      t.integer :status,             null: false, default: 0
      t.string  :last_error
      t.datetime :last_checked_at
      t.timestamps
    end
    add_index :mcp_servers, [ :user_id, :slug ], unique: true
  end
end
