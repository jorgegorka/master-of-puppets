module TerminalSession::Sweepable
  extend ActiveSupport::Concern

  DETACH_TTL = ENV.fetch("MOP_TERMINAL_TTL_HOURS", "1").to_i.hours

  included do
    scope :sweepable, -> { detached.where("last_activity_at < ?", Time.current - DETACH_TTL) }
  end

  class_methods do
    # Iteration is isolated: one row's terminate! raising must not abort the
    # rest of the sweep. terminate! itself only swallows the documented
    # supervisor-close failure modes; anything else (DB constraint, exotic
    # exception) is logged and skipped here so a single bad row can't strand
    # the rest of the detached rows past their TTL.
    def sweep!
      count = 0
      sweepable.find_each do |terminal|
        terminal.terminate!
        count += 1
      rescue StandardError => e
        Rails.logger.error("[TerminalSession.sweep!] id=#{terminal.id} failed: #{e.class}: #{e.message}")
      end
      count
    end
  end
end
