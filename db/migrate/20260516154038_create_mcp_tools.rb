class CreateMcpTools < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_tools do |t|
      t.references :mcp_server, null: false, foreign_key: true
      t.string   :name,         null: false
      t.text     :description
      t.json     :input_schema, null: false, default: {}
      t.datetime :discovered_at
      t.timestamps
    end
    add_index :mcp_tools, [:mcp_server_id, :name], unique: true
    add_index :mcp_tools, :name
  end
end
