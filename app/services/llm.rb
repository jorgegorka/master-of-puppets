module Llm
  class Error < StandardError; end

  class PingFailed < Error; end

  class RateLimited < Error
    attr_reader :retry_after

    def initialize(retry_after:, message: nil)
      super(message || "rate limited")
      @retry_after = retry_after
    end
  end

  class ToolLoopExceeded < Error; end
end
