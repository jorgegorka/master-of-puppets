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

  # Three-step open: create the row, ask the supervisor to spawn the tmux
  # session, then flip to :live. Wrapping the whole sequence in a transaction
  # means a supervisor failure (RPC error, path-traversal rejection, IOError)
  # rolls the row back atomically — there's no compensating session.destroy
  # call that could itself raise and leave an orphan :starting row behind.
  # (A leftover tmux process is preferable to a phantom DB row the UI keeps
  # showing; the next sweep cleans tmux up on its own.)
  def self.open!(user:, cwd:, cols: 120, rows: 40)
    transaction do
      session = user.terminal_sessions.create!(cwd: cwd, cols: cols, rows: rows)
      Terminal::TmuxManager.create(session)
      session.attach!
      session
    end
  end

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

  # DB flip happens first, supervisor close is best-effort afterwards: keeping
  # the RPC inside the transaction means an IOError / JSON::ParserError / etc.
  # from a misbehaving supervisor rolls the row back and leaves the user
  # staring at a "dead" session that the UI still thinks is live. The reverse
  # order — DB committed before the external call — preserves the visible
  # state regardless of supervisor health.
  def terminate!
    transaction do
      update!(status: :terminated, last_activity_at: Time.current)
      track_event :terminated
    end
    safe_supervisor_close
  end

  # Channel input/output passes through the model so neither the channel nor
  # any future caller has to know about Terminal::TmuxManager directly — the
  # model is the only thing that mutates terminal state.
  def write(data)
    Terminal::TmuxManager.send_keys(self, data)
  end

  def resize_to(cols, rows)
    Terminal::TmuxManager.resize(self, cols, rows)
  end

  def capture_scrollback(lines: 500)
    Terminal::TmuxManager.capture(self, lines: lines)
  end

  def fifo_path
    Terminal::TmuxManager.fifo_path(self)
  end

  private

  def assign_tmux_session_name
    self.tmux_session_name ||= "mop-term-#{SecureRandom.hex(4)}"
  end

  def default_last_activity_at
    self.last_activity_at ||= Time.current
  end

  # Best-effort: if the supervisor is down, half-responsive, or returns a
  # malformed line, we still want the row flipped to :terminated so the
  # user isn't stuck looking at a dead session in the UI. Catch every
  # failure mode AgentsSupervisor::Client.call can surface — including
  # the JSON / IO ones that aren't covered by the supervisor's own
  # SupervisorError wrapper — and log the rest. The bare-rescue arm
  # ensures Terminal::SweepJob#perform never aborts mid-batch.
  def safe_supervisor_close
    AgentsSupervisor::Client.call("terminal.close", { session_id: id })
  rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPIPE,
         AgentsSupervisor::SupervisorError, Timeout::Error,
         IOError, JSON::ParserError => e
    Rails.logger.warn("[TerminalSession #{id}] supervisor close failed: #{e.class}: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[TerminalSession #{id}] supervisor close unexpected error: #{e.class}: #{e.message}")
  end
end
