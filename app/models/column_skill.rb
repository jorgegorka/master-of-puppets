class ColumnSkill < ApplicationRecord
  belongs_to :column, inverse_of: :column_skills
  belongs_to :skill

  validates :skill_id, uniqueness: { scope: :column_id }
end
