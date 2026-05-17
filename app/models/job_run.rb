class JobRun < ApplicationRecord
  include Eventable

  belongs_to :scheduled_job
  belongs_to :chat_session, optional: true

  enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4 }

  scope :recent,   -> { order(created_at: :desc) }
  scope :finished, -> { where(status: %i[succeeded failed cancelled]) }

  def duration_seconds
    return nil unless started_at && finished_at

    (finished_at - started_at).round(2)
  end
end
