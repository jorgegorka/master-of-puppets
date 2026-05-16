class CreateSkillEnablements < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_enablements do |t|
      t.references :skill, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.datetime   :enabled_at, null: false

      t.timestamps
    end
    add_index :skill_enablements, %i[skill_id user_id], unique: true
  end
end
