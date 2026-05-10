class Column < ApplicationRecord
  include Tenantable
  include Auditable
  include ConfigVersioned
  include Triggerable
  include Notifiable

  include Columns::Triggering
  include Columns::Budgeting
  include Columns::Broadcasting
  include Columns::PromptBuilder
  include Columns::AgentConfiguration

  TRANSITION_POLICIES = %w[agent manual].freeze
  KINDS = %w[review done cancelled blocked].freeze
  SYSTEM_KEYS = %w[backlog in_progress review done cancelled blocked].freeze

  has_many :tasks, -> { order(:position) }, dependent: :restrict_with_error
  has_many :runs, dependent: :destroy
  has_many :column_skills, dependent: :destroy, inverse_of: :column
  has_many :skills, through: :column_skills
  has_many :outgoing_invocations,
           class_name: "SubAgentInvocation",
           through: :runs,
           source: :sub_agent_invocations

  enum :transition_policy, { agent: "agent", manual: "manual" }, validate: true

  validates :name, presence: true, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :project_id }
  validates :kind, inclusion: { in: KINDS }, allow_nil: true
  validates :system_key, inclusion: { in: SYSTEM_KEYS }, uniqueness: { scope: :project_id }, allow_nil: true
  validates :max_concurrent_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :budget_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validates :api_token, uniqueness: true, if: :agent?, allow_nil: true
  validates :adapter_type, presence: true, if: :agent_configured?
  validates :adapter_config, presence: true, if: :agent_configured?
  validates :job_spec, presence: true, if: :agent_configured?
  validates :success_criteria, presence: true, if: :agent_configured?

  attr_writer :preloaded_monthly_spend_cents

  def preloaded_monthly_spend_cents
    @preloaded_monthly_spend_cents
  end

  scope :agent_driven,  -> { where(transition_policy: :agent) }
  scope :manual_only,   -> { where(transition_policy: :manual) }
  scope :terminal,      -> { where(terminal: true) }
  scope :non_terminal,  -> { where(terminal: false) }
  scope :ordered,       -> { order(:position) }
  scope :visible,       -> { where(hidden_by_default: false) }
  scope :for_system,    ->(key) { where(system_key: key) }

  before_validation :nullify_agent_fields_on_manual
  before_validation :ensure_api_token, if: :agent?
  before_validation :assign_position, on: :create

  after_create_commit  :audit_created
  before_destroy       :audit_destroyed

  def agent?
    transition_policy == "agent"
  end

  def manual?
    transition_policy == "manual"
  end

  def terminal?
    !!terminal
  end

  # An agent column is "configured" when it has an adapter chosen.
  # Unconfigured agent columns are allowed (so seeded defaults are valid)
  # but cannot run until the user fills in adapter + prompts.
  def agent_configured?
    agent? && adapter_type.present?
  end

  def runnable?
    agent_configured? && job_spec.present? && success_criteria.present?
  end

  def regenerate_api_token!
    raise "Cannot rotate token on a manual column" unless agent?
    update!(api_token: self.class.generate_api_token)
  end

  def runs_eligible_tasks
    tasks.includes(:column).select { |t| !t.column.terminal? }
  end

  def self.generate_api_token
    SecureRandom.urlsafe_base64(32)
  end

  def self.find_by_api_token(token)
    return nil if token.blank?
    find_by(api_token: token)
  end

  private

  def audit_created
    actor = audit_actor
    return unless actor
    record_audit_event!(actor: actor, action: "column_created", metadata: { name: name, transition_policy: transition_policy })
  end

  def nullify_agent_fields_on_manual
    return unless transition_policy == "manual"
    self.job_spec = nil
    self.success_criteria = nil
    self.adapter_type = nil
    self.adapter_config = {}
    self.api_token = nil
    self.budget_cents = 0
    self.max_concurrent_runs = 1
    self.resumable_session = false
  end

  def ensure_api_token
    self.api_token ||= self.class.generate_api_token
  end

  def assign_position
    return if position.present?
    next_position = (project&.columns&.maximum(:position) || 0) + 1
    self.position = next_position
  end
end
