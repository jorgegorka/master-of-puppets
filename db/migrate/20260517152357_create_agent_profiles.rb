class CreateAgentProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_profiles do |t|
      t.string  :slug,         null: false
      t.string  :display_name, null: false
      t.string  :role,         null: false
      t.string  :model,        null: false
      t.string  :provider,     null: false
      t.json    :specialties,  default: [], null: false
      t.json    :avoid_tasks,  default: [], null: false
      t.string  :cwd,          null: false
      t.integer :status,       null: false, default: 2     # 0=online, 1=away, 2=offline
      t.boolean :enabled,      null: false, default: true
      t.string  :body_digest                                 # sha256 of YAML stanza body — used by Loadable
      t.timestamps
    end
    add_index :agent_profiles, :slug, unique: true
    add_index :agent_profiles, [ :enabled, :status ]
  end
end
