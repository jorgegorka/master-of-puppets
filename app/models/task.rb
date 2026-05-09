class Task < ApplicationRecord
  include Tenantable
  include Auditable
  include Triggerable
  include Hookable
  include Tasks::ProjectScoping
  include Tasks::Broadcasting
  include Tasks::CompletionTracking
  include Tasks::Reviewing
  include Tasks::Assignment
  include Tasks::Recurrence

  belongs_to :creator, class_name: "Role"
  belongs_to :assignee, class_name: "Role"
  belongs_to :reviewed_by, class_name: "Role", optional: true
  belongs_to :parent_task, class_name: "Task", optional: true

  has_many :subtasks, class_name: "Task", foreign_key: :parent_task_id, inverse_of: :parent_task, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :hook_executions, dependent: :destroy
  has_many :role_runs, dependent: :nullify
  has_many :task_evaluations, dependent: :destroy

  has_many :task_documents, dependent: :destroy, inverse_of: :task
  has_many :documents, through: :task_documents

  enum :status, { open: 0, in_progress: 1, blocked: 2, completed: 3, cancelled: 4, pending_review: 5 }, validate: true
  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, default: :medium, validate: true

  BOARD_COLUMNS = %w[open in_progress blocked pending_review completed cancelled].freeze

  validates :title, presence: true
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :completion_percentage, numericality: { only_integer: true, in: 0..100 }

  scope :active, -> { where.not(status: [ :completed, :cancelled ]) }
  scope :completed, -> { where(status: :completed) }
  scope :by_priority, -> { order(priority: :desc, created_at: :desc) }
  scope :roots, -> { where(parent_task_id: nil) }
  scope :blocked, -> { where(status: :blocked) }
  scope :overdue, -> { where("due_at < ?", Time.current).where.not(status: [ :completed, :cancelled ]) }
  scope :pending_human_review, -> { where(status: :pending_review).where.not(parent_task_id: nil).where(creator_id: Role.roots.select(:id)) }

  before_validation :default_assignee_to_creator
  before_save :set_completed_at
  after_commit :enqueue_hooks_for_transition, on: [ :create, :update ]
  after_commit :enqueue_validation_feedback, on: [ :create, :update ]

  after_create_commit :audit_created
  before_destroy :audit_destroyed

  def cost_in_dollars
    return nil unless cost_cents
    cost_cents / 100.0
  end

  def terminal?
    completed? || cancelled?
  end

  def root_ancestor
    node = self
    node = node.parent_task while node.parent_task_id
    node
  end

  def root?
    parent_task_id.nil?
  end

  # Returns the root task that should receive an auto-summary because approval
  # of this subtask just completed every sibling, or nil if no summary is due.
  def auto_summarizable_root
    return nil if root?
    root = root_ancestor
    total = root.subtasks.count
    return nil if total.zero?
    return nil unless root.subtasks.completed.count == total
    return nil if root.summary.present?
    root
  end

  # Enqueues a SummarizeTask sub-agent for the just-completed root, if one
  # is due. Called after a successful ReviewTask so the orchestrator never
  # has to remember to summarize.
  def chain_auto_summary_later!(parent_role_run:)
    root = auto_summarizable_root
    return unless root
    SubAgents::SummarizeTask.enqueue(
      role: parent_role_run.role,
      arguments: { "task_id" => root.id },
      parent_role_run: parent_role_run,
      input_summary: "task_id=#{root.id}"
    )
    root
  end

  def descendant_ids
    ids = []
    frontier = [ id ]
    until frontier.empty?
      frontier = self.class.where(parent_task_id: frontier).pluck(:id)
      ids.concat(frontier)
    end
    ids
  end

  # Post a comment from an automated source (role agent, watchdog, etc).
  # Swallows validation failures so notification bugs never prevent the
  # caller from completing its primary side effect.
  def post_system_comment(author:, body:)
    messages.create!(author: author, message_type: :comment, body: body)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[Task##{id}] could not post system comment: #{e.message}")
    nil
  end

  private

  def default_assignee_to_creator
    self.creator ||= project.roles.roots.order(:created_at).first
    self.assignee ||= creator
  end

  def set_completed_at
    if status_changed? && completed?
      self.completed_at = Time.current
    elsif status_changed? && !completed?
      self.completed_at = nil
    end
  end

  def audit_created
    actor = audit_actor
    return unless actor

    record_audit_event!(actor: actor, action: "created", metadata: { title: title, priority: priority })

    if assignee.present?
      record_audit_event!(actor: actor, action: "assigned", metadata: { assignee_id: assignee_id, assignee_name: assignee.title })
    end
  end
end
