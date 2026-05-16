module Llm
  module Pricing
    class UnknownModel < StandardError; end

    # Pricing per million tokens (USD). Anthropic only for Phase 1.
    TABLE = {
      "anthropic" => {
        "claude-opus-4-7"   => { input: 15.0, output: 75.0, cache_read: 1.5, cache_write: 18.75 },
        "claude-sonnet-4-6" => { input:  3.0, output: 15.0, cache_read: 0.3, cache_write:  3.75 },
        "claude-haiku-4-5"  => { input:  1.0, output:  5.0, cache_read: 0.1, cache_write:  1.25 }
      }
    }.transform_values { |models| models.transform_values(&:freeze).freeze }.freeze

    module_function

    def compute(provider:, model:, prompt_tokens:, completion_tokens:, cache_read_tokens: 0, cache_creation_tokens: 0)
      rates = TABLE.dig(provider, model)
      raise UnknownModel, "#{provider}/#{model}" unless rates

      total = (prompt_tokens.to_i        * rates[:input]) +
              (completion_tokens.to_i    * rates[:output]) +
              (cache_read_tokens.to_i    * rates[:cache_read]) +
              (cache_creation_tokens.to_i * rates[:cache_write])

      (total / 1_000_000.0).round(6)
    end

    def models_for(provider)
      TABLE.fetch(provider, {}).keys
    end
  end
end
