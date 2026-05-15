module Llm
  module Client
    module_function

    def for(provider:)
      config = ProviderConfig.find_by!(provider: provider)
      case provider
      when "anthropic"
        Anthropic.new(config)
      when "openai"
        OpenAi.new(config)
      when "ollama"
        Ollama.new(config)
      else
        raise ArgumentError, "unknown provider #{provider.inspect}"
      end
    end
  end
end
