class TerminalChannel < ApplicationCable::Channel
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
      Terminal::TmuxManager.send_keys(@terminal_session, data["data"].to_s)
    when "resize"
      Terminal::TmuxManager.resize(@terminal_session, data["cols"].to_i, data["rows"].to_i)
    end
  rescue AgentsSupervisor::SupervisorError, Errno::ENOENT, Errno::ECONNREFUSED => e
    Rails.logger.warn("[TerminalChannel] receive #{data['type'].inspect} failed: #{e.class}: #{e.message}")
  end

  def unsubscribed
    @pump_thread&.kill
    @pump_thread = nil
    @terminal_session&.detach! if @terminal_session&.live?
  end

  private
    def transmit_scrollback
      result     = Terminal::TmuxManager.capture(@terminal_session)
      scrollback = result&.[]("text").to_s
      transmit({ type: "scrollback", data: scrollback }) if scrollback.present?
    rescue AgentsSupervisor::SupervisorError, Errno::ENOENT, Errno::ECONNREFUSED => e
      Rails.logger.warn("[TerminalChannel] scrollback failed: #{e.class}: #{e.message}")
    end

    # The FIFO is created by the supervisor at terminal.create time. The
    # pump thread tails it and broadcasts each chunk to this channel's
    # stream — chunks are O(KB) and we round-trip them as-is, letting
    # xterm.js parse the ANSI/VT escapes.
    def start_pump
      fifo = Terminal::TmuxManager.fifo_path(@terminal_session)
      return unless fifo.exist?

      target = @terminal_session  # capture for the thread closure
      @pump_thread = Thread.new do
        begin
          File.open(fifo.to_s, "r") do |f|
            while (chunk = f.readpartial(4096))
              TerminalChannel.broadcast_to(target, { type: "chunk", data: chunk })
            end
          end
        rescue EOFError, IOError, Errno::EBADF
          # FIFO closed (tmux session ended) — exit cleanly.
        rescue => e
          Rails.logger.warn("[TerminalChannel] pump exited: #{e.class}: #{e.message}")
        end
      end
    end
end
