class CreateJobRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :job_runs do |t|
      t.references :scheduled_job, null: false, foreign_key: true
      t.references :chat_session,                  foreign_key: true  # nullable until #run! creates it
      t.datetime :started_at
      t.datetime :finished_at
      t.integer  :status, default: 0, null: false
      t.text     :output
      t.integer  :exit_code
      t.integer  :prompt_tokens
      t.integer  :completion_tokens
      t.integer  :cache_read_tokens
      t.integer  :cache_creation_tokens
      t.decimal  :cost_usd, precision: 12, scale: 6
      t.text     :error_message
      t.timestamps
    end
    add_index :job_runs, %i[scheduled_job_id created_at]
    add_index :job_runs, :status
  end
end
