require "socket"

module AgentsSupervisor
  # Rails-side subscriber for the supervisor's server-initiated
  # `memory.changed` notifications. One client per Puma worker — Phase 4
  # supervisor v2 collapses these into a single client-per-host.
  class Client
    SOCKET_PATH    = Rails.root.join("tmp/sockets/agents_supervisor.sock").freeze
    RETRY_INTERVAL = 2

    def self.subscribe_to_memory_changes
      client = new
      thread = Thread.new { client.run }
      at_exit { client.stop! }
      [ client, thread ]
    end

    def initialize
      @shutting_down = false
      @socket_mutex  = Mutex.new
      @socket        = nil
    end

    # Flip the shutdown flag and close the active socket. Closing wakes a
    # consume loop that's parked in a blocking `each_line` read — without
    # this, the flag alone would only fire on the next inbound line, which
    # for an idle supervisor can be never.
    def stop!
      @shutting_down = true
      @socket_mutex.synchronize do
        @socket&.close rescue nil
        @socket = nil
      end
    end

    def run
      until @shutting_down
        begin
          UNIXSocket.open(SOCKET_PATH.to_s) do |socket|
            @socket_mutex.synchronize { @socket = socket }
            consume(socket)
          end
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          sleep RETRY_INTERVAL unless @shutting_down
        rescue IOError
          # Socket was closed from `stop!` — exit cleanly.
        rescue => e
          Rails.logger.error("[AgentsSupervisor::Client] #{e.class}: #{e.message}")
          sleep RETRY_INTERVAL unless @shutting_down
        ensure
          @socket_mutex.synchronize { @socket = nil }
        end
      end
    end

    # Public for tests so we can drive consumption against an in-memory IO.
    def consume(socket)
      socket.each_line do |line|
        break if @shutting_down
        message = parse(line)
        next unless message && message["method"] == "memory.changed"

        paths = Array(message.dig("params", "paths"))
        paths.each { |path| Memory::IndexerJob.perform_later(path) }
      end
    rescue IOError
      # `stop!` closed the socket while we were parked in `each_line` —
      # treat it as a clean exit. Run-loop handles any other I/O errors.
      raise unless @shutting_down
    end

    private
      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
  end
end
