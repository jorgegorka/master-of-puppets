class AddTimelineIndexesToTaskEvaluations < ActiveRecord::Migration[8.1]
  def change
    add_index :task_evaluations, [ :task_id, :created_at ], name: "index_task_evaluations_on_task_id_and_created_at"
    add_index :task_evaluations, [ :role_id, :created_at ], name: "index_task_evaluations_on_role_id_and_created_at"
  end
end
