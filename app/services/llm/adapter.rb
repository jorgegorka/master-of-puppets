module Llm
  module Adapter
    # Yields normalized events as plain Ruby hashes. Each adapter implements this
    # contract for its provider.
    #
    # @param messages [Array<Hash>] history only (no role:system entries)
    # @param tools    [Array<Hash>] tool definitions (name, description, input_schema)
    # @param model    [String]
    # @param system   [String, nil] system prompt; passed as a top-level kwarg
    # @yieldparam event [Hash]
    # @return [Hash] usage summary { prompt_tokens:, completion_tokens:,
    #                                cache_read_tokens:, cache_creation_tokens:,
    #                                finish_reason: }
    def stream(messages:, tools:, model:, system: nil, &block)
      raise NotImplementedError
    end

    # Lightweight liveness check. Should raise Llm::PingFailed on error.
    def ping
      raise NotImplementedError
    end
  end
end
