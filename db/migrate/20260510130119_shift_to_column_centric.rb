class ShiftToColumnCentric < ActiveRecord::Migration[8.1]
  def up
    raise "destructive squash; run db:reset" if defined?(Project) && Project.exists?

    drop_role_dependent_tables_and_columns
    create_columns_table
    create_runs_table
    create_column_skills_table
    reshape_tasks_table
    reshape_messages_table
    reshape_audit_events_table
    reshape_task_evaluations_table
    reshape_sub_agent_invocations_table
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def drop_role_dependent_tables_and_columns
    if foreign_key_exists?(:tasks, column: :assignee_id)
      remove_foreign_key :tasks, column: :assignee_id
    end
    if foreign_key_exists?(:tasks, column: :creator_id)
      remove_foreign_key :tasks, column: :creator_id
    end
    if foreign_key_exists?(:tasks, column: :reviewed_by_id)
      remove_foreign_key :tasks, column: :reviewed_by_id
    end

    # Surviving tables that referenced soon-to-be-dropped tables
    if foreign_key_exists?(:task_evaluations, :roles)
      remove_foreign_key :task_evaluations, :roles
    end
    if foreign_key_exists?(:sub_agent_invocations, :role_runs)
      remove_foreign_key :sub_agent_invocations, :role_runs
    end

    remove_index :tasks, column: [ :assignee_id, :status ], if_exists: true
    remove_index :tasks, column: :assignee_id, if_exists: true
    remove_index :tasks, column: :creator_id, if_exists: true
    remove_index :tasks, column: :reviewed_by_id, if_exists: true
    remove_index :tasks, column: [ :project_id, :status ], if_exists: true

    remove_column :tasks, :assignee_id, :bigint
    remove_column :tasks, :creator_id, :bigint
    remove_column :tasks, :reviewed_by_id, :integer
    remove_column :tasks, :status, :integer

    drop_table :hook_executions, if_exists: true
    drop_table :role_hooks, if_exists: true
    drop_table :role_runs, if_exists: true
    drop_table :role_skills, if_exists: true
    drop_table :pending_hires, if_exists: true
    drop_table :approval_gates, if_exists: true
    drop_table :heartbeat_events, if_exists: true
    drop_table :roles, if_exists: true
    drop_table :role_categories, if_exists: true
  end

  def create_columns_table
    create_table :columns do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :transition_policy, null: false
      t.integer :position, null: false
      t.boolean :terminal, null: false, default: false
      t.string :kind
      t.string :system_key
      t.boolean :hidden_by_default, null: false, default: false
      t.integer :config_version, null: false, default: 1
      t.text :job_spec
      t.text :success_criteria
      t.string :adapter_type
      t.json :adapter_config, null: false, default: {}
      t.integer :budget_cents, null: false, default: 0
      t.integer :max_concurrent_runs, null: false, default: 1
      t.boolean :resumable_session, null: false, default: false
      t.string :api_token

      t.timestamps
    end

    add_index :columns, [ :project_id, :position ], unique: true
    add_index :columns, [ :project_id, :name ], unique: true
    add_index :columns, [ :project_id, :system_key ],
              unique: true,
              where: "system_key IS NOT NULL",
              name: "index_columns_on_project_and_system_key"
    add_index :columns, [ :project_id, :transition_policy ]
    add_index :columns, :api_token,
              unique: true,
              where: "api_token IS NOT NULL",
              name: "index_columns_on_api_token"
  end

  def create_runs_table
    create_table :runs do |t|
      t.references :column, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :initiating_user, foreign_key: { to_table: :users }
      t.string :status, null: false
      t.string :trigger_type, null: false
      t.string :claude_session_id
      t.integer :cost_cents, null: false, default: 0
      t.text :log_output
      t.datetime :started_at
      t.datetime :last_activity_at
      t.datetime :finished_at
      t.string :error_class
      t.text :error_message

      t.timestamps
    end

    add_index :runs, [ :column_id, :status ]
    add_index :runs, [ :project_id, :status ]
    add_index :runs, [ :task_id, :created_at ]
    add_index :runs, :claude_session_id
    add_index :runs, [ :status, :last_activity_at ]
    add_index :runs, [ :column_id, :task_id ],
              unique: true,
              where: "status IN ('queued', 'throttled', 'running')",
              name: "index_active_runs_on_column_and_task"
  end

  def create_column_skills_table
    create_table :column_skills do |t|
      t.references :column, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true

      t.timestamps
    end

    add_index :column_skills, [ :column_id, :skill_id ], unique: true
  end

  def reshape_tasks_table
    add_reference :tasks, :column, null: false, foreign_key: true
    add_column :tasks, :entered_column_at, :datetime, null: false
    add_column :tasks, :position, :integer, null: false
    add_column :tasks, :reviewer_feedback, :text
    add_reference :tasks, :creator_user, null: false, foreign_key: { to_table: :users }
    add_reference :tasks, :reviewed_by_user, foreign_key: { to_table: :users }

    add_index :tasks, [ :column_id, :position ]
    add_index :tasks, [ :project_id, :column_id ]
  end

  def reshape_messages_table
    add_reference :messages, :column, foreign_key: true
    add_reference :messages, :run, foreign_key: true
  end

  def reshape_audit_events_table
    change_column_null :audit_events, :actor_id, true
    change_column_null :audit_events, :actor_type, true
  end

  def reshape_task_evaluations_table
    add_reference :task_evaluations, :evaluator_column, null: false, foreign_key: { to_table: :columns }
    add_reference :task_evaluations, :evaluator_run, foreign_key: { to_table: :runs }

    remove_index :task_evaluations, column: [ :role_id, :created_at ], if_exists: true
    remove_index :task_evaluations, column: :role_id, if_exists: true
    remove_column :task_evaluations, :role_id, :integer

    add_index :task_evaluations, [ :evaluator_column_id, :created_at ]
  end

  def reshape_sub_agent_invocations_table
    add_reference :sub_agent_invocations, :parent_run, null: false, foreign_key: { to_table: :runs }
    remove_index :sub_agent_invocations, column: [ :role_run_id, :created_at ], if_exists: true
    remove_index :sub_agent_invocations, column: :role_run_id, if_exists: true
    remove_column :sub_agent_invocations, :role_run_id, :integer

    add_index :sub_agent_invocations, [ :parent_run_id, :created_at ]
  end
end
