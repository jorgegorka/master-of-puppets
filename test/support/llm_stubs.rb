# Helper for tests that need to drive ScheduledJob#run! / Message#advance!
# without making real LLM API calls. Stubs Llm::Client.for to return an
# in-memory adapter that yields a fixed event sequence.
module LlmStubs
  # Make every helper callable both as an instance method (when LlmStubs is
  # included into ActiveSupport::TestCase) AND as a module method
  # (e.g. `LlmStubs.with_decomposition(...)`).
  extend self

  # Replace Llm::Client.for with a block that returns the given adapter.
  # Restores the original method via ensure.
  def with_stubbed_llm(adapter)
    original = Llm::Client.method(:for)
    Llm::Client.singleton_class.define_method(:for) { |provider:| adapter }
    yield
  ensure
    Llm::Client.singleton_class.define_method(:for, &original)
  end

  # Non-block variant for system tests, where wrapping the entire test body in
  # a block is awkward. Patches Llm::Client.for for the lifetime of the test;
  # ApplicationSystemTestCase calls restore_llm_adapter in teardown.
  def stub_llm_adapter_with_completion(text)
    adapter = StubAdapter.new(text: text)
    @_original_llm_client_for = Llm::Client.method(:for)
    Llm::Client.singleton_class.define_method(:for) { |provider:| adapter }
  end

  def restore_llm_adapter
    return unless defined?(@_original_llm_client_for) && @_original_llm_client_for

    original = @_original_llm_client_for
    Llm::Client.singleton_class.define_method(:for, &original)
    @_original_llm_client_for = nil
  end

  # Wraps a decomposition plan into a JSON-fenced assistant reply and stubs
  # Llm::Client.for. If the caller passes a String, send it as-is (lets us
  # test malformed input).
  def with_decomposition(plan, &block)
    text = case plan
           when String then plan
           else "```json\n#{plan.to_json}\n```"
           end
    with_stubbed_llm(StubAdapter.new(text: text), &block)
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
