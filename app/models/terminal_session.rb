class TerminalSession < ApplicationRecord
  include Eventable
  include Sweepable

  belongs_to :user

  enum :status, { starting: 0, live: 1, detached: 2, terminated: 3 }, default: :starting

  validates :tmux_session_name, presence: true, uniqueness: true
  validates :cwd, presence: true

  before_validation :assign_tmux_session_name, on: :create
  before_validation :default_last_activity_at, on: :create

  scope :reattachable, -> { detached.where("last_activity_at > ?", Sweepable::DETACH_TTL.ago) }

  def attach!
    transaction do
      update!(status: :live, last_activity_at: Time.current)
      track_event :attached
    end
  end

  def detach!
    transaction do
      update!(status: :detached, last_activity_at: Time.current)
      track_event :detached
    end
  end

  def terminate!
    transaction do
      safe_supervisor_close
      update!(status: :terminated, last_activity_at: Time.current)
      track_event :terminated
    end
  end

  private
    def assign_tmux_session_name
      self.tmux_session_name ||= "mop-term-#{SecureRandom.hex(4)}"
    end

    def default_last_activity_at
      self.last_activity_at ||= Time.current
    end

    # The supervisor RPC is best-effort during terminate!: if the supervisor
    # is down, the row still flips to :terminated so the user isn't stuck
    # looking at a dead session in the UI. Don't rescue Exception — only the
    # specific failure modes for a missing/unreachable supervisor.
    def safe_supervisor_close
      AgentsSupervisor::Client.call("terminal.close", { session_id: id })
    rescue Errno::ENOENT, Errno::ECONNREFUSED, AgentsSupervisor::SupervisorError, Timeout::Error => e
      Rails.logger.warn("[TerminalSession #{id}] supervisor close failed: #{e.class}: #{e.message}")
    end
end
