class DropRedundantTimestamps < ActiveRecord::Migration[8.1]
  def change
    remove_column :skill_installations, :accepted_at, :datetime, null: false
    remove_column :skill_enablements,   :enabled_at,  :datetime, null: false
  end
end
