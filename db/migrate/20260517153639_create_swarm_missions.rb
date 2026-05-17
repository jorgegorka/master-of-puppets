class CreateSwarmMissions < ActiveRecord::Migration[8.1]
  def change
    create_table :swarm_missions do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string  :title, null: false
      t.text    :goal,  null: false
      t.integer :state, null: false, default: 0    # planning=0, dispatching=1, executing=2,
                                                   # reviewing=3, blocked=4, complete=5, cancelled=6
      t.integer :mode,  null: false, default: 0    # auto=0, manual=1
      t.text    :decomposition_notes
      t.timestamps
    end
    add_index :swarm_missions, [ :user_id, :state ]
  end
end
