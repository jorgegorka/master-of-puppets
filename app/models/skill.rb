class Skill < ApplicationRecord
  include Eventable
  include Searchable
  searchable_via SkillFts, foreign_key: :skill_id

  include Skill::Loadable
  include Skill::SecurityAnalyzable
  include Skill::Installable
  include Skill::Enableable

  enum :origin,         { builtin: 0, agent_created: 1, marketplace: 2 }
  enum :security_level, { safe: 0, low: 1, medium: 2, high: 3 }

  validates :slug, presence: true, uniqueness: true
  validates :name, :category, :source_path, :body_digest, presence: true

  # Associations live in Skill::Installable / Skill::Enableable (included above).
  scope :enabled_for,   ->(user) { joins(:enablements).where(skill_enablements: { user_id: user.id }) }
  scope :installed_for, ->(user) { joins(:installations).where(skill_installations: { user_id: user.id }) }
end
