class SubAgentInvocation < ApplicationRecord
  include Tenantable

  belongs_to :parent_run, class_name: "Run", inverse_of: :sub_agent_invocations

  enum :status, { running: 0, completed: 1, failed: 2, queued: 3 }

  validates :sub_agent_name, presence: true
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :iterations, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }

  def self.start!(parent_run:, sub_agent_name:, input_summary: nil)
    create!(
      parent_run: parent_run,
      project: parent_run.project,
      sub_agent_name: sub_agent_name,
      status: :running,
      input_summary: input_summary
    )
  end

  def self.enqueue!(parent_run:, sub_agent_name:, input_summary: nil)
    create!(
      parent_run: parent_run,
      project: parent_run.project,
      sub_agent_name: sub_agent_name,
      status: :queued,
      input_summary: input_summary
    )
  end

  def mark_running!
    update!(status: :running)
  end

  def terminal?
    completed? || failed?
  end

  def as_tool_payload
    {
      id: id,
      sub_agent: sub_agent_name,
      status: status,
      input_summary: input_summary,
      result_summary: result_summary,
      error_message: error_message,
      cost_cents: cost_cents,
      duration_ms: duration_ms,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  def finish!(result_summary:, cost_cents:, duration_ms:, iterations:)
    transaction do
      update!(
        status: :completed,
        result_summary: result_summary,
        cost_cents: cost_cents,
        duration_ms: duration_ms,
        iterations: iterations
      )
      roll_cost_into_parent_run!
    end
  end

  def fail!(error_message:, cost_cents: 0, duration_ms: nil, iterations: 0)
    transaction do
      update!(
        status: :failed,
        error_message: error_message,
        cost_cents: cost_cents,
        duration_ms: duration_ms,
        iterations: iterations
      )
      roll_cost_into_parent_run!
    end
  end

  private

  def roll_cost_into_parent_run!
    return unless cost_cents.to_i > 0
    Run.update_counters(parent_run_id, cost_cents: cost_cents)
  end
end
