class Run < ApplicationRecord
  include Tenantable

  include Runs::Lifecycle
  include Runs::Costing

  class BudgetExceeded < StandardError; end

  STATUSES = %w[queued running throttled completed failed cancelled budget_exceeded].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled budget_exceeded].freeze
  ACTIVE_STATUSES = %w[queued throttled running].freeze

  TRIGGER_TYPES = %w[task_entered manual recurrence resume].freeze

  belongs_to :column
  belongs_to :task
  belongs_to :initiating_user, class_name: "User", optional: true

  has_many :sub_agent_invocations, foreign_key: :parent_run_id, dependent: :destroy
  has_many :messages, dependent: :nullify

  enum :status, STATUSES.index_with(&:to_s), validate: true
  enum :trigger_type, TRIGGER_TYPES.index_with(&:to_s), validate: true

  scope :active,   -> { where(status: ACTIVE_STATUSES) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }
  scope :recent,   -> { where("created_at > ?", 24.hours.ago) }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  # Resumable session: if the column allows resume and a prior run exists for
  # the same (column, task), reuse its claude_session_id.
  def resumable_session_id
    return nil unless column.resumable_session?
    column.runs
          .where(task_id: task_id)
          .where.not(id: id)
          .where.not(claude_session_id: nil)
          .order(created_at: :desc)
          .pick(:claude_session_id)
  end

  def append_log!(text)
    return if text.blank?
    self.class.where(id: id).update_all(
      [ "log_output = COALESCE(log_output, '') || ?, last_activity_at = ?", text, Time.current ]
    )
  end

  def broadcast_line!(text)
    return if text.blank?
    append_log!(text)
    Turbo::StreamsChannel.broadcast_append_to(
      "run_#{id}",
      target: "run-output",
      partial: "runs/log_line",
      locals: { text: text }
    )
  rescue ActionView::Template::Error
    # broadcast best-effort
  end
end
