# Helper for tests that need to drive ScheduledJob#run! / Message#advance!
# without making real LLM API calls. Stubs Llm::Client.for to return an
# in-memory adapter that yields a fixed event sequence.
module LlmStubs
  # Replace Llm::Client.for with a block that returns the given adapter.
  # Restores the original method via ensure.
  def with_stubbed_llm(adapter)
    original = Llm::Client.method(:for)
    Llm::Client.singleton_class.define_method(:for) { |provider:| adapter }
    yield
  ensure
    Llm::Client.singleton_class.define_method(:for, &original)
  end

  # Simple adapter that yields a "completed text response" event sequence.
  class StubAdapter
    DEFAULT_USAGE = {
      prompt_tokens: 12,
      completion_tokens: 7,
      cache_read_tokens: 0,
      cache_creation_tokens: 0,
      finish_reason: "end_turn"
    }.freeze

    def initialize(text:, usage: DEFAULT_USAGE)
      @text  = text
      @usage = usage
    end

    def stream(messages:, tools:, model:, system: nil)
      yield(type: :message_start, message_id: "msg_stub", model: model)
      yield(type: :content_block_start, index: 0, block: { type: "text", text: "" })
      yield(type: :text_delta, index: 0, text: @text)
      yield(type: :content_block_stop, index: 0)
      yield(type: :message_stop, finish_reason: @usage[:finish_reason])
      @usage
    end
  end

  # Adapter that raises mid-stream to exercise the failure path.
  class RaisingAdapter
    def initialize(error_class: RuntimeError, message: "boom")
      @error_class = error_class
      @message     = message
    end

    def stream(**)
      raise @error_class, @message
    end
  end
end

ActiveSupport::TestCase.include(LlmStubs)
