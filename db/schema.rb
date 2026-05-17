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

ActiveRecord::Schema[8.1].define(version: 2026_05_17_152357) do
  create_table "agent_profiles", force: :cascade do |t|
    t.json "avoid_tasks", default: [], null: false
    t.string "body_digest"
    t.datetime "created_at", null: false
    t.string "cwd", null: false
    t.string "display_name", null: false
    t.boolean "enabled", default: true, null: false
    t.string "model", null: false
    t.string "provider", null: false
    t.string "role", null: false
    t.string "slug", null: false
    t.json "specialties", default: [], null: false
    t.integer "status", default: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["enabled", "status"], name: "index_agent_profiles_on_enabled_and_status"
    t.index ["slug"], name: "index_agent_profiles_on_slug", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "prefix", null: false
    t.json "scopes", default: [], null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["prefix"], name: "index_api_tokens_on_prefix", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "chat_session_archives", force: :cascade do |t|
    t.integer "chat_session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["chat_session_id"], name: "index_chat_session_archives_on_chat_session_id", unique: true
    t.index ["user_id"], name: "index_chat_session_archives_on_user_id"
  end

  create_table "chat_session_pins", force: :cascade do |t|
    t.integer "chat_session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["chat_session_id"], name: "index_chat_session_pins_on_chat_session_id", unique: true
    t.index ["user_id"], name: "index_chat_session_pins_on_user_id"
  end

  create_table "chat_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "forked_from_id"
    t.datetime "last_active_at"
    t.string "model", null: false
    t.string "provider", null: false
    t.string "share_token"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["forked_from_id"], name: "index_chat_sessions_on_forked_from_id"
    t.index ["share_token"], name: "index_chat_sessions_on_share_token", unique: true, where: "share_token IS NOT NULL"
    t.index ["user_id"], name: "index_chat_sessions_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.integer "creator_id"
    t.integer "eventable_id", null: false
    t.string "eventable_type", null: false
    t.string "ip"
    t.datetime "occurred_at", null: false
    t.json "particulars"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["action"], name: "index_events_on_action"
    t.index ["creator_id"], name: "index_events_on_creator_id"
    t.index ["eventable_type", "eventable_id"], name: "index_events_on_eventable_type_and_eventable_id"
    t.index ["occurred_at"], name: "index_events_on_occurred_at"
  end

  create_table "job_runs", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cache_read_tokens"
    t.integer "chat_session_id"
    t.integer "completion_tokens"
    t.decimal "cost_usd", precision: 12, scale: 6
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "exit_code"
    t.datetime "finished_at"
    t.text "output"
    t.integer "output_truncated_at_bytes"
    t.integer "prompt_tokens"
    t.integer "scheduled_job_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["chat_session_id"], name: "index_job_runs_on_chat_session_id"
    t.index ["scheduled_job_id", "created_at"], name: "index_job_runs_on_scheduled_job_id_and_created_at"
    t.index ["scheduled_job_id"], name: "index_job_runs_on_scheduled_job_id"
    t.index ["status"], name: "index_job_runs_on_status"
  end

  create_table "mcp_servers", force: :cascade do |t|
    t.text "auth_payload"
    t.integer "auth_type", default: 0, null: false
    t.string "command_template"
    t.datetime "created_at", null: false
    t.text "env_payload"
    t.datetime "last_checked_at"
    t.string "last_error"
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.json "tool_list", default: []
    t.integer "tool_mode", default: 0, null: false
    t.integer "transport_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.index ["user_id", "slug"], name: "index_mcp_servers_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_mcp_servers_on_user_id"
  end

  create_table "mcp_tools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discovered_at"
    t.json "input_schema", default: {}, null: false
    t.integer "mcp_server_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["mcp_server_id", "name"], name: "index_mcp_tools_on_mcp_server_id_and_name", unique: true
    t.index ["mcp_server_id"], name: "index_mcp_tools_on_mcp_server_id"
    t.index ["name"], name: "index_mcp_tools_on_name"
  end

  create_table "memory_files", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "disk_mtime", null: false
    t.string "path", null: false
    t.json "tags", default: []
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["disk_mtime"], name: "index_memory_files_on_disk_mtime"
    t.index ["path"], name: "index_memory_files_on_path", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cache_read_tokens"
    t.integer "chat_session_id", null: false
    t.integer "completion_tokens"
    t.json "content_blocks"
    t.decimal "cost_usd", precision: 12, scale: 6
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "model"
    t.integer "prompt_tokens"
    t.string "provider"
    t.integer "role", null: false
    t.integer "status", default: 0, null: false
    t.json "stream_cursor"
    t.datetime "updated_at", null: false
    t.index ["chat_session_id", "created_at"], name: "index_messages_on_chat_session_id_and_created_at"
    t.index ["chat_session_id"], name: "index_messages_on_chat_session_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
  end

  create_table "provider_configs", force: :cascade do |t|
    t.text "api_key"
    t.string "base_url"
    t.datetime "created_at", null: false
    t.string "default_model"
    t.boolean "enabled", default: false, null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_provider_configs_on_provider", unique: true
  end

  create_table "scheduled_job_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "reason"
    t.integer "scheduled_job_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["scheduled_job_id"], name: "index_scheduled_job_pauses_on_scheduled_job_id"
    t.index ["scheduled_job_id"], name: "index_scheduled_job_pauses_on_sjid_unique", unique: true
    t.index ["user_id"], name: "index_scheduled_job_pauses_on_user_id"
  end

  create_table "scheduled_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cron", null: false
    t.datetime "last_run_at"
    t.string "model", null: false
    t.string "name", null: false
    t.datetime "next_run_at"
    t.text "prompt", null: false
    t.string "provider", null: false
    t.json "skill_slugs", default: [], null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["next_run_at"], name: "index_scheduled_jobs_on_next_run_at"
    t.index ["user_id", "name"], name: "index_scheduled_jobs_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_scheduled_jobs_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "skill_enablements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "skill_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["skill_id", "user_id"], name: "index_skill_enablements_on_skill_id_and_user_id", unique: true
    t.index ["skill_id"], name: "index_skill_enablements_on_skill_id"
    t.index ["user_id"], name: "index_skill_enablements_on_user_id"
  end

  create_table "skill_installations", force: :cascade do |t|
    t.integer "accepted_security_level", null: false
    t.datetime "created_at", null: false
    t.integer "skill_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["skill_id", "user_id"], name: "index_skill_installations_on_skill_id_and_user_id", unique: true
    t.index ["skill_id"], name: "index_skill_installations_on_skill_id"
    t.index ["user_id"], name: "index_skill_installations_on_user_id"
  end

  create_table "skills", force: :cascade do |t|
    t.string "body_digest", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discovered_at", null: false
    t.json "manifest", default: {}, null: false
    t.string "name", null: false
    t.integer "origin", default: 0, null: false
    t.integer "security_level", default: 0, null: false
    t.string "slug", null: false
    t.string "source_path", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_skills_on_category"
    t.index ["security_level"], name: "index_skills_on_security_level"
    t.index ["slug"], name: "index_skills_on_slug", unique: true
  end

  create_table "terminal_sessions", force: :cascade do |t|
    t.integer "cols", default: 120, null: false
    t.datetime "created_at", null: false
    t.string "cwd", null: false
    t.datetime "last_activity_at", null: false
    t.integer "rows", default: 40, null: false
    t.integer "status", default: 0, null: false
    t.string "tmux_session_name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["tmux_session_name"], name: "index_terminal_sessions_on_tmux_session_name", unique: true
    t.index ["user_id", "status"], name: "index_terminal_sessions_on_user_id_and_status"
    t.index ["user_id"], name: "index_terminal_sessions_on_user_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.json "input"
    t.integer "message_id", null: false
    t.string "name", null: false
    t.json "output"
    t.string "provider_tool_id", null: false
    t.integer "source", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "provider_tool_id"], name: "index_tool_calls_on_message_id_and_provider_tool_id", unique: true
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
  end

  create_table "user_settings", force: :cascade do |t|
    t.string "accent", default: "indigo", null: false
    t.datetime "created_at", null: false
    t.integer "editor_font_size", default: 13, null: false
    t.boolean "notifications_enabled", default: true, null: false
    t.boolean "sidebar_collapsed", default: false, null: false
    t.string "theme", default: "claude-official", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_threshold", default: 80, null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_user_settings_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.boolean "single_user_bootstrap", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "api_tokens", "users"
  add_foreign_key "chat_session_archives", "chat_sessions"
  add_foreign_key "chat_session_archives", "users"
  add_foreign_key "chat_session_pins", "chat_sessions"
  add_foreign_key "chat_session_pins", "users"
  add_foreign_key "chat_sessions", "chat_sessions", column: "forked_from_id"
  add_foreign_key "chat_sessions", "users"
  add_foreign_key "events", "users", column: "creator_id"
  add_foreign_key "job_runs", "chat_sessions"
  add_foreign_key "job_runs", "scheduled_jobs"
  add_foreign_key "mcp_servers", "users"
  add_foreign_key "mcp_tools", "mcp_servers"
  add_foreign_key "messages", "chat_sessions"
  add_foreign_key "scheduled_job_pauses", "scheduled_jobs"
  add_foreign_key "scheduled_job_pauses", "users"
  add_foreign_key "scheduled_jobs", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "skill_enablements", "skills"
  add_foreign_key "skill_enablements", "users"
  add_foreign_key "skill_installations", "skills"
  add_foreign_key "skill_installations", "users"
  add_foreign_key "terminal_sessions", "users"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "user_settings", "users"
end
