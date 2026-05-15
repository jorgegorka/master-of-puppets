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

ActiveRecord::Schema[8.1].define(version: 2026_05_15_205129) do
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

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
  add_foreign_key "events", "users", column: "creator_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "user_settings", "users"
end
