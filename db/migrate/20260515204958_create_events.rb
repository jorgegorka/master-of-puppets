class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :creator, null: true, foreign_key: { to_table: :users }
      t.string  :action,         null: false
      t.string  :eventable_type, null: false
      t.integer :eventable_id,   null: false
      t.json    :particulars
      t.string  :ip
      t.string  :user_agent
      t.datetime :occurred_at,   null: false

      t.timestamps
    end
    add_index :events, [ :eventable_type, :eventable_id ]
    add_index :events, :action
    add_index :events, :occurred_at
  end
end
