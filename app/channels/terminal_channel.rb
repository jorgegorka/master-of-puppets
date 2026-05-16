class TerminalChannel < ApplicationCable::Channel
  # Pump threads outlive a single channel instance: ActionCable can swap a new
  # channel in (reconnect, page navigation, websocket flap) while the previous
  # one's pump is still parked in a blocking FIFO read. The per-instance
  # @pump_thread reference goes away with the old channel, so without a class-
  # level registry we'd leak one zombie reader per reconnect. Keyed by
  # terminal_session_id so reconnects to the same session reliably reap.
  @@pump_threads = {}
  @@pump_mutex   = Mutex.new

  def subscribed
    @terminal_session = current_user.terminal_sessions.find_by(id: params[:terminal_session_id])
    if @terminal_session.nil? || @terminal_session.terminated?
      Rails.logger.info("[TerminalChannel] reject: user=#{current_user.id} terminal_session_id=#{params[:terminal_session_id]}")
      reject and return
    end

    stream_for @terminal_session
    @terminal_session.attach!

    transmit_scrollback
    start_pump
  end

  def receive(data)
    return unless @terminal_session

    case data["type"]
    when "input"
      @terminal_session.write(data["data"].to_s)
    when "resize"
      @terminal_session.resize_to(data["cols"].to_i, data["rows"].to_i)
    end
  rescue AgentsSupervisor::SupervisorError, Errno::ENOENT, Errno::ECONNREFUSED => e
    Rails.logger.warn("[TerminalChannel] receive #{data['type'].inspect} failed: #{e.class}: #{e.message}")
  end

  def unsubscribed
    stop_pump
    @terminal_session&.detach! if @terminal_session&.live?
  end

  private

  def transmit_scrollback
    result     = @terminal_session.capture_scrollback
    scrollback = result&.[]("text").to_s
    transmit({ type: "scrollback", data: scrollback }) if scrollback.present?
  rescue AgentsSupervisor::SupervisorError, Errno::ENOENT, Errno::ECONNREFUSED => e
    Rails.logger.warn("[TerminalChannel] scrollback failed: #{e.class}: #{e.message}")
  end

  # The FIFO is created by the supervisor at terminal.create time. The
  # pump thread tails it and broadcasts each chunk to this channel's
  # stream — chunks are O(KB) and we round-trip them as-is, letting
  # xterm.js parse the ANSI/VT escapes.
  #
  # Open is non-blocking (File::NONBLOCK): a plain File.open(fifo, "r")
  # parks until a writer exists, which means a missing or stalled
  # supervisor would deadlock the pump thread forever (and survive a
  # client reconnect because the new channel instance can't reach the
  # old @pump_thread reference). Combined with read_nonblock + IO.select,
  # the thread is always interruptible by stop_pump.
  def start_pump
    fifo = @terminal_session.fifo_path
    return unless fifo.exist?

    stop_pump # reap any pump still tied to this session before opening another

    target = @terminal_session
    tsid   = @terminal_session.id
    thread = Thread.new do
      f = File.open(fifo.to_s, File::RDONLY | File::NONBLOCK)
      begin
        pump_loop(f, target)
      ensure
        begin
          f.close
        rescue StandardError
          nil
        end
      end
    rescue EOFError, IOError, Errno::EBADF
      # FIFO closed (tmux session ended) — exit cleanly.
    rescue StandardError => e
      Rails.logger.warn("[TerminalChannel #{tsid}] pump exited: #{e.class}: #{e.message}")
    ensure
      @@pump_mutex.synchronize { @@pump_threads.delete(tsid) if @@pump_threads[tsid] == Thread.current }
    end

    @@pump_mutex.synchronize { @@pump_threads[tsid] = thread }
  end

  def pump_loop(io, target)
    loop do
      chunk = io.read_nonblock(4096)
      # read_nonblock returns "" on EOF in some Ruby/libc combos rather
      # than raising EOFError; treat empty reads as EOF so we don't burn
      # CPU spinning over a dead pipe.
      break if chunk.nil? || chunk.empty?

      TerminalChannel.broadcast_to(target, { type: "chunk", data: chunk })
    rescue IO::WaitReadable
      # Park until either data arrives or Thread#kill interrupts the
      # select — the latter is how stop_pump terminates this thread.
      IO.select([ io ], nil, nil, 1.0)
    rescue EOFError
      break
    end
  end

  def stop_pump
    tsid = @terminal_session&.id
    return unless tsid

    previous = @@pump_mutex.synchronize { @@pump_threads.delete(tsid) }
    previous&.kill
  end
end
