class SkillEnablement < ApplicationRecord
  belongs_to :skill
  belongs_to :user

  validates :skill_id, uniqueness: { scope: :user_id }
end
