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
    end

    def stop!
      @shutting_down = true
    end

    def run
      until @shutting_down
        begin
          UNIXSocket.open(SOCKET_PATH.to_s) do |socket|
            consume(socket)
          end
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          sleep RETRY_INTERVAL
        rescue => e
          Rails.logger.error("[AgentsSupervisor::Client] #{e.class}: #{e.message}")
          sleep RETRY_INTERVAL
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
    end

    private
      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
  end
end
