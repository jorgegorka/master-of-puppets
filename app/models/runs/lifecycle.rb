module Runs
  module Lifecycle
    extend ActiveSupport::Concern

    included do
      after_commit :on_terminal_dispatch_next, if: :reached_terminal?
    end

    def start!
      raise "Cannot start a #{status} run" unless queued?
      now = Time.current
      update!(status: :running, started_at: now, last_activity_at: now)
    end

    def record_activity!
      self.class.where(id: id).update_all(last_activity_at: Time.current)
    end

    def mark_throttled!
      raise "Cannot throttle a #{status} run" unless queued? || throttled?
      update!(status: :throttled)
    end

    def finish!(status:, error: nil)
      raise ArgumentError, "Unknown status: #{status}" unless Run::TERMINAL_STATUSES.include?(status.to_s)
      raise "Cannot finish a #{self.status} run" if terminal?

      attrs = {
        status: status,
        finished_at: Time.current
      }
      if error
        attrs[:error_class]   = error.class.name
        attrs[:error_message] = error.message
      end
      update!(attrs)
    end

    def cancel!
      raise "Cannot cancel a #{status} run" if terminal?
      update!(status: :cancelled, finished_at: Time.current)
    end

    private

    def reached_terminal?
      saved_change_to_status? && terminal?
    end

    def on_terminal_dispatch_next
      project.dispatch_next_throttled_run!
    rescue StandardError => e
      Rails.logger.warn("[Run##{id}] dispatch_next_throttled_run failed: #{e.message}")
    end
  end
end
