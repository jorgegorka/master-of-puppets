class Skill < ApplicationRecord
  include Eventable
  include Searchable
  searchable_via SkillFts, foreign_key: :skill_id,
                 columns: %i[slug name category description body]

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

  # Skills change either by user action (install/enable, reload from /skills/:id)
  # or by the supervisor watcher firing Skill::ReloadJob. Re-broadcast the whole
  # list so creates/updates/destroys (and new categories) all surface on /skills
  # without a refresh. Cheaper bespoke patches would need extra DOM container
  # scaffolding per category — the full re-render is simpler and the list size
  # is bounded by the on-disk skill count.
  after_commit :broadcast_skills_list, on: %i[create update destroy]

  # Tool surface a skill contributes when its prompt section is loaded.
  # Frontmatter declares names under `tools:`; each one is looked up against
  # the Tool::Internal registry and converted to a provider tool definition.
  # A skill with no `tools:` (or unknown names) injects prompt-only — no
  # tools — which keeps low-trust skills additive but unable to widen the
  # tool surface the chat session would otherwise have.
  # Tool surface this skill contributes for a given user. The user gate is
  # enforced here (via Tool::Internal.allowed_for) so that a skill whose
  # frontmatter declares an admin-only tool (e.g. `run_shell`) cannot smuggle
  # it back to a non-admin through the skills path. Allowed names are the
  # intersection of what the skill declares and what the user may use.
  def tool_definitions(user:)
    allowed_names = Tool::Internal.allowed_for(user).map { |d| d[:name] }.to_set
    Array(manifest["tools"]).filter_map do |tool_name|
      next unless allowed_names.include?(tool_name)
      Tool::Internal.lookup(tool_name)&.tool_definition
    end
  end

  private
    def broadcast_skills_list
      broadcast_replace_to "skills",
        target:  "skills_list",
        partial: "skills/list",
        locals:  { skills_by_category: Skill.all.order(:category, :name).group_by(&:category) }
    end
end
