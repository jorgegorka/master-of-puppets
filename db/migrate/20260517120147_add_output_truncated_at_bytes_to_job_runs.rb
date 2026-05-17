class AddOutputTruncatedAtBytesToJobRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :job_runs, :output_truncated_at_bytes, :integer
  end
end
