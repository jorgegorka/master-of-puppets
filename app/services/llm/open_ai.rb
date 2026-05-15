module Llm
  class OpenAi
    include Adapter

    def initialize(config)
      @config = config
    end

    def stream(messages:, tools:, model:, &block)
      raise NotImplementedError, "OpenAI adapter lands in Phase 7"
    end

    def ping
      raise NotImplementedError, "OpenAI adapter lands in Phase 7"
    end
  end
end
