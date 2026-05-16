module TerminalSession::Sweepable
  extend ActiveSupport::Concern

  DETACH_TTL = ENV.fetch("MOP_TERMINAL_TTL_HOURS", "1").to_i.hours

  included do
    scope :sweepable, -> { detached.where("last_activity_at < ?", Time.current - DETACH_TTL) }
  end

  class_methods do
    def sweep!
      count = 0
      sweepable.find_each do |terminal|
        terminal.terminate!
        count += 1
      end
      count
    end
  end
end
