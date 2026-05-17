module ScheduledJob::Pausable
  extend ActiveSupport::Concern

  included do
    has_one :pause_record, class_name: "ScheduledJob::Pause",
                           foreign_key: :scheduled_job_id,
                           dependent: :destroy
    scope :paused, -> { joins(:pause_record) }
    scope :active, -> { where.missing(:pause_record) }
  end

  def paused?
    pause_record.present?
  end

  def active?
    !paused?
  end

  def pause(reason: nil, user: Current.user)
    unless paused?
      transaction do
        create_pause_record!(user: user, reason: reason)
        track_event :paused, creator: user, reason: reason
      end
    end
  end

  def resume(user: Current.user)
    if paused?
      transaction do
        pause_record.destroy!
        track_event :resumed, creator: user
      end
    end
  end
end
