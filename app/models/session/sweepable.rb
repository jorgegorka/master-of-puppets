module Session::Sweepable
  extend ActiveSupport::Concern

  DEFAULT_TTL_DAYS  = ENV.fetch("MOP_SESSION_TTL_DAYS", "30").to_i
  DEFAULT_TTL       = DEFAULT_TTL_DAYS.days
  ROTATION_WINDOW   = DEFAULT_TTL / 3
  CLOCK_SKEW_MARGIN = 60.seconds

  included do
    before_create { self.expires_at ||= Time.current + DEFAULT_TTL }

    scope :expired, -> { where("expires_at < ?", Time.current - CLOCK_SKEW_MARGIN) }
    scope :active,  -> { where("expires_at >= ?", Time.current) }
  end

  def expired?
    expires_at <= Time.current
  end

  def expire!
    transaction do
      update!(expires_at: Time.current)
      track_event :expired
    end
  end

  def touch_and_maybe_rotate!
    now    = Time.current
    rotate = (expires_at - now) < ROTATION_WINDOW
    attrs  = { last_seen_at: now }
    attrs[:expires_at] = now + DEFAULT_TTL if rotate
    update_columns(attrs)
    track_event :rotated if rotate
  end

  class_methods do
    def sweep!
      count = 0
      expired.find_each do |session|
        session.destroy
        count += 1
      end
      count
    end
  end
end
