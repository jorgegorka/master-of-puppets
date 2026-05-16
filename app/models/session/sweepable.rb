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

  # Bumps last_seen_at on every request and *also* extends expires_at when
  # we're inside the rotation window — old name (`touch_and_maybe_rotate!`)
  # buried the rotation behind a "maybe". This name makes the rotation the
  # headline of what the method does on the days it matters.
  def touch_and_rotate_if_due!
    now    = Time.current
    rotate = (expires_at - now) < ROTATION_WINDOW
    attrs  = { last_seen_at: now }
    attrs[:expires_at] = now + DEFAULT_TTL if rotate
    transaction do
      update_columns(attrs)
      track_event :rotated if rotate
    end
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
