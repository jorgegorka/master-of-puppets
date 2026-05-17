class CreateSwarmCheckpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :swarm_checkpoints do |t|
      t.references :swarm_assignment, null: false, foreign_key: true
      t.string :state_label,          null: false
      t.json   :runtime_state,        default: {}, null: false
      t.json   :files_changed,        default: [], null: false
      t.json   :commands_run,         default: [], null: false
      t.text   :result
      t.text   :blocker
      t.text   :next_action
      t.text   :raw,                  null: false
      t.timestamps
    end
    add_index :swarm_checkpoints, [ :swarm_assignment_id, :created_at ]
  end
end
