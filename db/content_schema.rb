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

ActiveRecord::Schema[8.1].define(version: 2026_05_16_104044) do

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "memory_files_fts", "fts5", ["memory_file_id UNINDEXED", "path", "title", "tags", "body", "tokenize = 'porter'"]
  create_virtual_table "skills_fts", "fts5", ["skill_id UNINDEXED", "slug", "name", "category", "description", "body", "tokenize = 'porter'"]
end
