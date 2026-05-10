# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_10_130119) do
  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "actor_type"
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.bigint "project_id"
    t.index ["action"], name: "index_audit_events_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_events_on_actor"
    t.index ["auditable_type", "auditable_id", "created_at"], name: "index_audit_events_on_auditable_and_created_at"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_events_on_auditable"
    t.index ["project_id", "action"], name: "index_audit_events_on_project_and_action"
    t.index ["project_id", "created_at"], name: "index_audit_events_on_project_and_time"
    t.index ["project_id"], name: "index_audit_events_on_project_id"
  end

  create_table "column_skills", force: :cascade do |t|
    t.integer "column_id", null: false
    t.datetime "created_at", null: false
    t.integer "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["column_id", "skill_id"], name: "index_column_skills_on_column_id_and_skill_id", unique: true
    t.index ["column_id"], name: "index_column_skills_on_column_id"
    t.index ["skill_id"], name: "index_column_skills_on_skill_id"
  end

  create_table "columns", force: :cascade do |t|
    t.json "adapter_config", default: {}, null: false
    t.string "adapter_type"
    t.string "api_token"
    t.integer "budget_cents", default: 0, null: false
    t.integer "config_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "hidden_by_default", default: false, null: false
    t.text "job_spec"
    t.string "kind"
    t.integer "max_concurrent_runs", default: 1, null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.integer "project_id", null: false
    t.boolean "resumable_session", default: false, null: false
    t.text "success_criteria"
    t.string "system_key"
    t.boolean "terminal", default: false, null: false
    t.string "transition_policy", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_columns_on_api_token", unique: true, where: "api_token IS NOT NULL"
    t.index ["project_id", "name"], name: "index_columns_on_project_id_and_name", unique: true
    t.index ["project_id", "position"], name: "index_columns_on_project_id_and_position", unique: true
    t.index ["project_id", "system_key"], name: "index_columns_on_project_and_system_key", unique: true, where: "system_key IS NOT NULL"
    t.index ["project_id", "transition_policy"], name: "index_columns_on_project_id_and_transition_policy"
    t.index ["project_id"], name: "index_columns_on_project_id"
  end

  create_table "config_versions", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "author_id"
    t.string "author_type"
    t.json "changeset", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.json "snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "versionable_id", null: false
    t.string "versionable_type", null: false
    t.index ["author_type", "author_id"], name: "index_config_versions_on_author"
    t.index ["project_id"], name: "index_config_versions_on_project_id"
    t.index ["versionable_type", "versionable_id", "created_at"], name: "index_config_versions_on_versionable_and_time"
    t.index ["versionable_type", "versionable_id"], name: "index_config_versions_on_versionable"
  end

  create_table "document_taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id", null: false
    t.integer "document_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "document_tag_id"], name: "index_document_taggings_on_document_id_and_document_tag_id", unique: true
    t.index ["document_id"], name: "index_document_taggings_on_document_id"
    t.index ["document_tag_id"], name: "index_document_taggings_on_document_tag_id"
  end

  create_table "document_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_document_tags_on_project_id_and_name", unique: true
    t.index ["project_id"], name: "index_document_tags_on_project_id"
  end

  create_table "documents", force: :cascade do |t|
    t.integer "author_id", null: false
    t.string "author_type", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "last_editor_id"
    t.string "last_editor_type"
    t.integer "project_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_documents_on_author_type_and_author_id"
    t.index ["last_editor_type", "last_editor_id"], name: "index_documents_on_last_editor_type_and_last_editor_id"
    t.index ["project_id"], name: "index_documents_on_project_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "expires_at", null: false
    t.bigint "inviter_id", null: false
    t.bigint "project_id", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["project_id", "email_address"], name: "index_invitations_on_project_and_email_pending", unique: true, where: "(status = 0)"
    t.index ["project_id"], name: "index_invitations_on_project_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_memberships_on_project_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "author_type", null: false
    t.text "body", null: false
    t.integer "column_id"
    t.datetime "created_at", null: false
    t.integer "message_type", default: 0, null: false
    t.bigint "parent_id"
    t.integer "run_id"
    t.bigint "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_messages_on_author"
    t.index ["column_id"], name: "index_messages_on_column_id"
    t.index ["parent_id"], name: "index_messages_on_parent_id"
    t.index ["run_id"], name: "index_messages_on_run_id"
    t.index ["task_id", "created_at"], name: "index_messages_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_messages_on_task_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.bigint "notifiable_id"
    t.string "notifiable_type"
    t.bigint "project_id", null: false
    t.datetime "read_at"
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "updated_at", null: false
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["project_id", "created_at"], name: "index_notifications_on_project_and_time"
    t.index ["project_id"], name: "index_notifications_on_project_id"
    t.index ["recipient_type", "recipient_id", "read_at"], name: "index_notifications_on_recipient_and_read"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "max_concurrent_agents", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "runs", force: :cascade do |t|
    t.string "claude_session_id"
    t.integer "column_id", null: false
    t.integer "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "error_class"
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "initiating_user_id"
    t.datetime "last_activity_at"
    t.text "log_output"
    t.integer "project_id", null: false
    t.datetime "started_at"
    t.string "status", null: false
    t.integer "task_id", null: false
    t.string "trigger_type", null: false
    t.datetime "updated_at", null: false
    t.index ["claude_session_id"], name: "index_runs_on_claude_session_id"
    t.index ["column_id", "status"], name: "index_runs_on_column_id_and_status"
    t.index ["column_id", "task_id"], name: "index_active_runs_on_column_and_task", unique: true, where: "status IN ('queued', 'throttled', 'running')"
    t.index ["column_id"], name: "index_runs_on_column_id"
    t.index ["initiating_user_id"], name: "index_runs_on_initiating_user_id"
    t.index ["project_id", "status"], name: "index_runs_on_project_id_and_status"
    t.index ["project_id"], name: "index_runs_on_project_id"
    t.index ["status", "last_activity_at"], name: "index_runs_on_status_and_last_activity_at"
    t.index ["task_id", "created_at"], name: "index_runs_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_runs_on_task_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "skill_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id", null: false
    t.integer "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_skill_documents_on_document_id"
    t.index ["skill_id", "document_id"], name: "index_skill_documents_on_skill_id_and_document_id", unique: true
    t.index ["skill_id"], name: "index_skill_documents_on_skill_id"
  end

  create_table "skills", force: :cascade do |t|
    t.boolean "builtin", default: true, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.text "markdown", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "category"], name: "index_skills_on_project_id_and_category"
    t.index ["project_id", "key"], name: "index_skills_on_project_id_and_key", unique: true
    t.index ["project_id"], name: "index_skills_on_project_id"
  end

  create_table "sub_agent_invocations", force: :cascade do |t|
    t.integer "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.text "input_summary"
    t.integer "iterations", default: 0, null: false
    t.integer "parent_run_id", null: false
    t.integer "project_id", null: false
    t.text "result_summary"
    t.integer "status", default: 0, null: false
    t.string "sub_agent_name", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_run_id", "created_at"], name: "index_sub_agent_invocations_on_parent_run_id_and_created_at"
    t.index ["parent_run_id"], name: "index_sub_agent_invocations_on_parent_run_id"
    t.index ["project_id", "sub_agent_name"], name: "index_sub_agent_invocations_on_project_id_and_sub_agent_name"
    t.index ["project_id"], name: "index_sub_agent_invocations_on_project_id"
  end

  create_table "task_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_task_documents_on_document_id"
    t.index ["task_id", "document_id"], name: "index_task_documents_on_task_id_and_document_id", unique: true
    t.index ["task_id"], name: "index_task_documents_on_task_id"
  end

  create_table "task_evaluations", force: :cascade do |t|
    t.integer "attempt_number", null: false
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.integer "evaluator_column_id", null: false
    t.integer "evaluator_run_id"
    t.text "feedback", null: false
    t.integer "project_id", null: false
    t.integer "result", null: false
    t.integer "root_task_id", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluator_column_id", "created_at"], name: "index_task_evaluations_on_evaluator_column_id_and_created_at"
    t.index ["evaluator_column_id"], name: "index_task_evaluations_on_evaluator_column_id"
    t.index ["evaluator_run_id"], name: "index_task_evaluations_on_evaluator_run_id"
    t.index ["project_id"], name: "index_task_evaluations_on_project_id"
    t.index ["root_task_id"], name: "index_task_evaluations_on_root_task_id"
    t.index ["task_id", "attempt_number"], name: "index_task_evaluations_on_task_id_and_attempt_number", unique: true
    t.index ["task_id", "created_at"], name: "index_task_evaluations_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_task_evaluations_on_task_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "column_id", null: false
    t.datetime "completed_at"
    t.integer "completion_percentage", default: 0, null: false
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.integer "creator_user_id", null: false
    t.text "description"
    t.datetime "due_at"
    t.datetime "entered_column_at", null: false
    t.datetime "next_recurrence_at"
    t.bigint "parent_task_id"
    t.integer "position", null: false
    t.integer "priority", default: 1, null: false
    t.bigint "project_id", null: false
    t.datetime "recurrence_anchor_at"
    t.integer "recurrence_interval"
    t.datetime "recurrence_last_fired_at"
    t.string "recurrence_timezone"
    t.integer "recurrence_unit"
    t.datetime "reviewed_at"
    t.integer "reviewed_by_user_id"
    t.text "reviewer_feedback"
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["column_id", "position"], name: "index_tasks_on_column_id_and_position"
    t.index ["column_id"], name: "index_tasks_on_column_id"
    t.index ["creator_user_id"], name: "index_tasks_on_creator_user_id"
    t.index ["next_recurrence_at"], name: "index_tasks_on_next_recurrence_at"
    t.index ["parent_task_id"], name: "index_tasks_on_parent_task_id"
    t.index ["project_id", "column_id"], name: "index_tasks_on_project_id_and_column_id"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["reviewed_by_user_id"], name: "index_tasks_on_reviewed_by_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "audit_events", "projects"
  add_foreign_key "column_skills", "columns"
  add_foreign_key "column_skills", "skills"
  add_foreign_key "columns", "projects"
  add_foreign_key "config_versions", "projects"
  add_foreign_key "document_taggings", "document_tags"
  add_foreign_key "document_taggings", "documents"
  add_foreign_key "document_tags", "projects"
  add_foreign_key "documents", "projects"
  add_foreign_key "invitations", "projects"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "memberships", "projects"
  add_foreign_key "memberships", "users"
  add_foreign_key "messages", "columns"
  add_foreign_key "messages", "messages", column: "parent_id"
  add_foreign_key "messages", "runs"
  add_foreign_key "messages", "tasks"
  add_foreign_key "notifications", "projects"
  add_foreign_key "runs", "columns"
  add_foreign_key "runs", "projects"
  add_foreign_key "runs", "tasks"
  add_foreign_key "runs", "users", column: "initiating_user_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "skill_documents", "documents"
  add_foreign_key "skill_documents", "skills"
  add_foreign_key "skills", "projects"
  add_foreign_key "sub_agent_invocations", "projects"
  add_foreign_key "sub_agent_invocations", "runs", column: "parent_run_id"
  add_foreign_key "task_documents", "documents"
  add_foreign_key "task_documents", "tasks"
  add_foreign_key "task_evaluations", "columns", column: "evaluator_column_id"
  add_foreign_key "task_evaluations", "projects"
  add_foreign_key "task_evaluations", "runs", column: "evaluator_run_id"
  add_foreign_key "task_evaluations", "tasks"
  add_foreign_key "task_evaluations", "tasks", column: "root_task_id"
  add_foreign_key "tasks", "columns"
  add_foreign_key "tasks", "projects"
  add_foreign_key "tasks", "tasks", column: "parent_task_id"
  add_foreign_key "tasks", "users", column: "creator_user_id"
  add_foreign_key "tasks", "users", column: "reviewed_by_user_id"
end
