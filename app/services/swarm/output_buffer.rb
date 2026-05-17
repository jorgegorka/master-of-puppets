module Swarm
  # In-process per-assignment FIFO-drain buffer. Thread-safe; one instance
  # per Puma+SolidQueue worker. Held by Swarm::OrchestratorLoopJob between
  # ticks to avoid re-opening the FIFO every cycle.
  class OutputBuffer
    MAX_BUFFER_BYTES = 4 * 1024 * 1024

    def self.singleton
      @singleton ||= new
    end

    def initialize
      @mutex   = Mutex.new
      @buffers = Hash.new { |h, k| h[k] = +"" }
      @fifos   = {}
    end

    def drain(assignment)
      @mutex.synchronize do
        fifo = (@fifos[assignment.id] ||= File.open(Swarm::TmuxBridge.fifo_path(assignment), "r+"))
        loop do
          chunk = fifo.read_nonblock(64 * 1024)
          @buffers[assignment.id] << chunk
          SwarmChannel.broadcast_to(assignment.swarm_mission,
                                    { type: "worker_output", assignment_id: assignment.id, chunk: chunk })
          break if chunk.bytesize < 64 * 1024
        end
      rescue IO::WaitReadable, Errno::EAGAIN
        # No more data right now.
      rescue Errno::ENOENT
        # FIFO not yet created (supervisor hasn't dispatched).
      ensure
        enforce_cap(assignment.id)
      end
    end

    def consume(assignment_id)
      @mutex.synchronize do
        out = @buffers[assignment_id].dup
        @buffers[assignment_id].clear
        out
      end
    end

    def close(assignment_id)
      @mutex.synchronize do
        @fifos.delete(assignment_id)&.close rescue nil
        @buffers.delete(assignment_id)
      end
    end

    private
      def enforce_cap(id)
        buf = @buffers[id]
        if buf.bytesize > MAX_BUFFER_BYTES
          overflow = buf.bytesize - MAX_BUFFER_BYTES
          @buffers[id] = buf.byteslice(overflow, MAX_BUFFER_BYTES).to_s
        end
      end
  end
end
