class AuditEvent < ApplicationRecord
  include Chronological

  belongs_to :auditable, polymorphic: true
  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :project, optional: true

  validates :action, presence: true

  scope :for_action, ->(action_name) { where(action: action_name) }
  scope :for_project, ->(project) { where(project: project) }
  scope :for_actor_type, ->(type) { where(actor_type: type) }
  scope :for_date_range, ->(start_date, end_date) { where(created_at: start_date.beginning_of_day..end_date.end_of_day) }
  scope :filter_by_column, ->(filter) {
    if filter == "columns_only"
      where(actor_type: "Column")
    else
      column_id = filter.to_i
      column_id > 0 ? where(actor_type: "Column", actor_id: column_id) : all
    end
  }

  # Governance-specific action types
  GOVERNANCE_ACTIONS = %w[
    gate_approval
    gate_rejection
    gate_blocked
    emergency_stop
    emergency_resume
    role_paused
    role_resumed
    role_terminated
    config_rollback
    cost_recorded
    hook_executed
    validation_feedback_received
    goal_evaluation_exhausted
  ].freeze

  # Immutability: prevent updates to persisted records
  def readonly?
    persisted?
  end

  def governance_action?
    GOVERNANCE_ACTIONS.include?(action)
  end
end
