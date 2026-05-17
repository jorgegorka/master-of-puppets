class JobRun < ApplicationRecord
  include Eventable

  belongs_to :scheduled_job, inverse_of: :runs
  belongs_to :chat_session, optional: true

  enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4 }

  scope :recent,   -> { order(created_at: :desc) }
  scope :finished, -> { where(status: %i[succeeded failed cancelled]) }

  def duration_seconds
    return nil unless started_at && finished_at

    (finished_at - started_at).round(2)
  end

  def status_badge_modifier
    case status
    when "succeeded"           then "badge--ok"
    when "failed", "cancelled" then "badge--danger"
    when "pending", "running"  then "badge--warn"
    end
  end

  # Live-update the run row on the ScheduledJob#show page whenever status,
  # timing, cost, or output changes. The view subscribes via
  # `turbo_stream_from @scheduled_job`; the partial wraps the <li> in
  # `dom_id(run)` so the replace target matches.
  after_commit -> {
    broadcast_replace_to scheduled_job,
      target:  ActionView::RecordIdentifier.dom_id(self),
      partial: "scheduled_jobs/runs/run",
      locals:  { run: self }
  }, on: %i[create update]
end
