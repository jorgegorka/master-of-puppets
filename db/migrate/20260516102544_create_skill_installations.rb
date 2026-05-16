class CreateSkillInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_installations do |t|
      t.references :skill, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.integer    :accepted_security_level, null: false
      t.datetime   :accepted_at, null: false

      t.timestamps
    end
    add_index :skill_installations, %i[skill_id user_id], unique: true
  end
end
