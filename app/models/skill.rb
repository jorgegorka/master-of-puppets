class Skill < ApplicationRecord
  include Eventable
  include Skill::Loadable
  include Skill::SecurityAnalyzable

  enum :origin,         { builtin: 0, agent_created: 1, marketplace: 2 }
  enum :security_level, { safe: 0, low: 1, medium: 2, high: 3 }

  validates :slug, presence: true, uniqueness: true
  validates :name, :category, :source_path, :body_digest, presence: true

  scope :enabled_for,   ->(user) { joins(:enablements).where(skill_enablements: { user_id: user.id }) }
  scope :installed_for, ->(user) { joins(:installations).where(skill_installations: { user_id: user.id }) }
end
