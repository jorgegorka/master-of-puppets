module Llm
  class Anthropic
    include Adapter

    def initialize(config)
      @client = ::Anthropic::Client.new(
        api_key: config.api_key.to_s,
        base_url: config.base_url.presence || "https://api.anthropic.com"
      )
    end

    # Streams a model turn. Yields normalized events; returns a usage summary.
    def stream(messages:, tools:, model:, system: nil, &block)
      raw = @client.messages.stream(
        model:      model,
        max_tokens: 8_192,
        messages:   messages,
        tools:      tools.presence,
        system:     system.presence
      )

      raw.each do |event|
        normalized = normalize(event)
        block.call(normalized) if normalized
      end

      final = raw.accumulated_message
      usage = final.usage
      {
        prompt_tokens:         usage.input_tokens || 0,
        completion_tokens:     usage.output_tokens || 0,
        cache_read_tokens:     usage.cache_read_input_tokens || 0,
        cache_creation_tokens: usage.cache_creation_input_tokens || 0,
        finish_reason:         final.stop_reason
      }
    rescue ::Anthropic::Errors::RateLimitError => e
      retry_after = e.response&.headers&.dig("retry-after").to_i
      retry_after = 30 if retry_after.zero?
      raise Llm::RateLimited.new(retry_after: retry_after, message: e.message)
    end

    def ping
      @client.messages.create(
        model:      "claude-haiku-4-5",
        max_tokens: 1,
        messages:   [ { role: "user", content: "ping" } ]
      )
      true
    rescue => e
      raise Llm::PingFailed, e.message
    end

    private
      # The SDK's MessageStream yields a mix of raw streaming events (typed with
      # symbols :message_start, :content_block_start, :content_block_delta,
      # :content_block_stop, :message_delta, :message_stop) and convenience typed
      # events (:text, :input_json, :thinking) derived from the raw deltas. We
      # normalize only off the raw events — the typed ones would double-count.
      def normalize(event)
        case event.type
        when :message_start
          { type: :message_start, message_id: event.message.id, model: event.message.model }
        when :content_block_start
          { type: :content_block_start, index: event.index, block: event.content_block.to_h }
        when :content_block_delta
          normalize_delta(event)
        when :content_block_stop
          { type: :content_block_stop, index: event.index }
        when :message_delta
          { type: :message_delta, finish_reason: event.delta.stop_reason }
        when :message_stop
          { type: :message_stop, finish_reason: nil }
        end
      end

      def normalize_delta(event)
        case event.delta.type
        when :text_delta
          { type: :text_delta, index: event.index, text: event.delta.text }
        when :thinking_delta
          { type: :thinking_delta, index: event.index, thinking: event.delta.thinking }
        when :input_json_delta
          { type: :tool_use_input_delta, index: event.index, partial_json: event.delta.partial_json }
        end
      end
  end
end
