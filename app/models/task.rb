class Task < ApplicationRecord
  include Tenantable
  include Auditable
  include Triggerable
  include Tasks::ProjectScoping
  include Tasks::Broadcasting
  include Tasks::CompletionTracking
  include Tasks::Reviewing
  include Tasks::Recurrence
  include Tasks::ColumnFlow

  belongs_to :column, inverse_of: :tasks
  belongs_to :creator, class_name: "User", foreign_key: :creator_user_id, inverse_of: :created_tasks
  belongs_to :reviewer, class_name: "User", foreign_key: :reviewed_by_user_id, optional: true
  belongs_to :parent_task, class_name: "Task", optional: true

  has_many :subtasks, class_name: "Task", foreign_key: :parent_task_id, inverse_of: :parent_task, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :runs, dependent: :destroy
  has_many :task_evaluations, dependent: :destroy

  has_many :task_documents, dependent: :destroy, inverse_of: :task
  has_many :documents, through: :task_documents

  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, default: :medium, validate: true

  validates :title, presence: true
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :completion_percentage, numericality: { only_integer: true, in: 0..100 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :entered_column_at, presence: true

  attr_accessor :messages_count

  scope :active,                -> { joins(:column).where(columns: { terminal: false }) }
  scope :completed,             -> { joins(:column).where(columns: { kind: "done" }) }
  scope :cancelled,             -> { joins(:column).where(columns: { kind: "cancelled" }) }
  scope :blocked,               -> { joins(:column).where(columns: { system_key: "blocked" }) }
  scope :overdue,               -> { joins(:column).where("due_at < ?", Time.current).where(columns: { terminal: false }) }
  scope :pending_human_review,  -> { joins(:column).where(columns: { kind: "review" }) }
  scope :by_priority,           -> { order(priority: :desc, created_at: :desc) }
  scope :roots,                 -> { where(parent_task_id: nil) }

  before_validation :set_initial_column_state, on: :create
  before_validation :assign_position, on: :create

  after_create_commit  :audit_created
  after_create_commit  :trigger_initial_column_run
  after_create_commit  :trigger_mention_wakes
  before_destroy       :audit_destroyed

  def cost_in_dollars
    return nil unless cost_cents
    cost_cents / 100.0
  end

  def terminal?
    column&.terminal? == true
  end

  def completed?
    column&.kind == "done"
  end

  def cancelled?
    column&.kind == "cancelled"
  end

  def blocked?
    column&.system_key == "blocked"
  end

  def pending_review?
    column&.kind == "review"
  end

  def root_ancestor
    node = self
    node = node.parent_task while node.parent_task_id
    node
  end

  def root?
    parent_task_id.nil?
  end

  def auto_summarizable_root
    return nil if root?
    root = root_ancestor
    total = root.subtasks.count
    return nil if total.zero?
    return nil unless root.subtasks.completed.count == total
    return nil if root.summary.present?
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

  def post_system_comment(author:, body:)
    messages.create!(author: author, message_type: :comment, body: body)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[Task##{id}] could not post system comment: #{e.message}")
    nil
  end

  private

  def set_initial_column_state
    self.column ||= project&.columns&.non_terminal&.ordered&.first
    self.entered_column_at ||= Time.current
  end

  def assign_position
    return if position.present?
    return unless column
    self.position = (column.tasks.maximum(:position) || 0) + 1
  end

  def trigger_initial_column_run
    return unless column&.agent? && !column.terminal?
    TriggerColumnJob.perform_later(id)
  end

  def trigger_mention_wakes
    return unless project

    text = [ title, description ].compact_blank.join("\n")
    detect_mentions(text, project).each do |mentioned_column|
      mentioned_column.trigger_for(self, trigger_type: :task_entered)
    end
  end

  def audit_created
    actor = audit_actor
    return unless actor

    record_audit_event!(actor: actor, action: "created", metadata: { title: title, priority: priority })
  end
end
