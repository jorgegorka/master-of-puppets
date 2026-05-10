class Skill < ApplicationRecord
  include Tenantable

  has_many :column_skills, dependent: :destroy, inverse_of: :skill
  has_many :columns, through: :column_skills

  has_many :skill_documents, dependent: :destroy, inverse_of: :skill
  has_many :documents, through: :skill_documents

  validates :key, presence: true,
                  uniqueness: { scope: :project_id }
  validates :name, presence: true
  validates :markdown, presence: true

  scope :by_category, ->(cat) { where(category: cat) }
  scope :builtin, -> { where(builtin: true) }
  scope :custom, -> { where(builtin: false) }
end
