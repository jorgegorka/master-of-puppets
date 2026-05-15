module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  def track_event(action, creator: Current.user, **particulars)
    if should_track_event?
      events.create!(
        action: "#{eventable_prefix}_#{action}",
        creator: creator,
        particulars: particulars,
        ip: Current.ip_address,
        user_agent: Current.user_agent,
        occurred_at: Time.current
      )
    end
  end

  def event_was_created(event)
    # Override hook
  end

  private
    def should_track_event?
      true
    end

    def eventable_prefix
      self.class.name.demodulize.underscore
    end
end
