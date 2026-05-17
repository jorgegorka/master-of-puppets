class CreateSwarmMissionCancellations < ActiveRecord::Migration[8.1]
  def change
    create_table :swarm_mission_cancellations do |t|
      t.references :swarm_mission, null: false, foreign_key: true, index: { unique: true }
      t.references :user,          null: false, foreign_key: true
      t.string :reason
      t.timestamps
    end
  end
end
