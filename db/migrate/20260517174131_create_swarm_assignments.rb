class CreateSwarmAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :swarm_assignments do |t|
      t.references :swarm_mission, null: false, foreign_key: true
      t.references :agent_profile, null: false, foreign_key: true
      t.text    :task,             null: false
      t.text    :rationale
      t.json    :depends_on,       default: [],   null: false
      t.integer :state,            default: 0,    null: false
                # pending=0, dispatched=1, running=2, completed=3,
                # failed=4, blocked=5, cancelled=6
      t.boolean :review_required,  default: false, null: false
      t.string  :tmux_session_name             # set when dispatched
      t.text    :block_reason
      t.references :chat_session,  foreign_key: true
      t.datetime :dispatched_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :swarm_assignments, [ :swarm_mission_id, :state ]
  end
end
