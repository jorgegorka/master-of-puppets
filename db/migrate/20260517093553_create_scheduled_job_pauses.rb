class CreateScheduledJobPauses < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_job_pauses do |t|
      t.references :scheduled_job, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :reason
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    add_index :scheduled_job_pauses, :scheduled_job_id,
              unique: true, name: "index_scheduled_job_pauses_on_sjid_unique"
  end
end
