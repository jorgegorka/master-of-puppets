class CreateSkillsFts < ActiveRecord::Migration[8.1]
  COLUMNS = [
    "skill_id UNINDEXED",
    "slug",
    "name",
    "category",
    "description",
    "body",
    "tokenize = 'porter'"
  ].freeze

  def change
    create_virtual_table :skills_fts, :fts5, COLUMNS
  end
end
