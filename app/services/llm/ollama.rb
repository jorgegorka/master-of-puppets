module Llm
  class Ollama
    include Adapter

    def initialize(config)
      @config = config
    end

    def stream(messages:, tools:, model:, &block)
      raise NotImplementedError, "Ollama adapter lands in Phase 4 or 7"
    end

    def ping
      raise NotImplementedError, "Ollama adapter lands in Phase 4 or 7"
    end
  end
end
