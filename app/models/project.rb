class Project < ApplicationRecord
  include Projects::Seeding
  include Projects::Spend

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :columns, dependent: :destroy
  has_many :runs, dependent: :destroy
  has_many :skills, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :config_versions, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :document_tags, dependent: :destroy
  has_many :task_evaluations, dependent: :destroy
  has_many :sub_agent_invocations, dependent: :destroy
  has_many :audit_events, dependent: :delete_all

  validates :name, presence: true
  validates :max_concurrent_agents, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  def concurrent_agent_limit_reached?
    return false if max_concurrent_agents.zero?
    runs.where(status: %w[queued running]).count >= max_concurrent_agents
  end

  def dispatch_next_throttled_run!
    return if concurrent_agent_limit_reached?

    busy_column_ids = runs.where(status: %w[queued running]).select(:column_id)
    next_run = runs.where(status: :throttled)
                   .where.not(column_id: busy_column_ids)
                   .order(:created_at)
                   .first
    return unless next_run

    next_run.update!(status: :queued)
    ExecuteColumnJob.perform_later(next_run.id)
  end

  def approvals_pending_count
    tasks.pending_human_review.count
  end

  def cascade_adapter_config!(adapter_type:, adapter_config: {})
    columns.where(transition_policy: :agent)
           .update_all(adapter_type: adapter_type, adapter_config: adapter_config)
  end

  def admin_recipients
    memberships
      .where(role: %i[owner admin])
      .includes(:user)
      .map(&:user)
  end
end
