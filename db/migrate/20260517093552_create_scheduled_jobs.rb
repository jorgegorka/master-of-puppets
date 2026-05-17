class CreateScheduledJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name,        null: false
      t.string  :cron,        null: false
      t.text    :prompt,      null: false
      t.string  :model,       null: false
      t.string  :provider,    null: false
      t.json    :skill_slugs, default: [], null: false
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.timestamps
    end
    add_index :scheduled_jobs, :next_run_at
    add_index :scheduled_jobs, %i[user_id name], unique: true
  end
end
