class CreateSwarmEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :swarm_events do |t|
      t.references :swarm_mission,    null: false, foreign_key: true
      t.references :swarm_assignment, null: true,  foreign_key: true
      t.string   :kind,        null: false
      t.text     :message
      t.json     :data,        default: {},  null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :swarm_events, [ :swarm_mission_id, :occurred_at ]
  end
end
