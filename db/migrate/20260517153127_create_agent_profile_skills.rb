class CreateAgentProfileSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_profile_skills do |t|
      t.references :agent_profile, null: false, foreign_key: true
      t.references :skill,         null: false, foreign_key: true
      t.timestamps
    end
    add_index :agent_profile_skills, [ :agent_profile_id, :skill_id ], unique: true
  end
end
