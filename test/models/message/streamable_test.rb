require "test_helper"

class Message::StreamableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    provider_configs(:anthropic).update!(api_key: "test")
  end

  test "advance! streams a complete turn and persists tokens" do
    session = chat_sessions(:one)
    session.messages.create!(role: :user, content_blocks: [ { type: "text", text: "hi" } ], status: :completed, model: "claude-opus-4-7", provider: "anthropic")
    assistant = session.messages.create!(role: :assistant, status: :pending, content_blocks: [], model: "claude-opus-4-7", provider: "anthropic")

    fake_adapter = build_fake_adapter(
      events: [
        { type: :content_block_start, index: 0, block: { type: "text", text: "" } },
        { type: :text_delta, index: 0, text: "Hi" },
        { type: :text_delta, index: 0, text: " there" },
        { type: :content_block_stop, index: 0 },
        { type: :message_stop, finish_reason: "end_turn" }
      ],
      usage: {
        prompt_tokens: 10, completion_tokens: 3,
        cache_read_tokens: 0, cache_creation_tokens: 0,
        finish_reason: "end_turn"
      }
    )
    assistant.define_singleton_method(:llm_adapter) { fake_adapter }

    assistant.advance!
    assistant.reload

    assert_equal "completed", assistant.status
    assert_equal 10, assistant.prompt_tokens
    assert_equal 3,  assistant.completion_tokens
    assert_predicate assistant.cost_usd, :positive?
    assert_equal 1, assistant.content_blocks.size
    assert_equal "text", assistant.content_blocks.first["type"]
    assert_equal "Hi there", assistant.content_blocks.first["text"]
    assert_equal 1, Event.where(action: "message_completed").count
  end

  test "advance! marks status rate_limited and reschedules" do
    assistant = build_assistant
    fake_adapter = build_fake_adapter(raise_error: Llm::RateLimited.new(retry_after: 5, message: "slow down"))
    assistant.define_singleton_method(:llm_adapter) { fake_adapter }

    assert_enqueued_with(job: Message::AdvanceJob) { assistant.advance! }
    assert_equal "rate_limited", assistant.reload.status
  end

  test "advance! marks status failed and re-raises on other errors" do
    assistant = build_assistant
    fake_adapter = build_fake_adapter(raise_error: RuntimeError.new("boom"))
    assistant.define_singleton_method(:llm_adapter) { fake_adapter }

    assert_raises(RuntimeError) { assistant.advance! }
    assistant.reload
    assert_equal "failed", assistant.status
    assert_equal "boom", assistant.error_message
    assert Event.where(action: "message_failed").exists?
  end

  test "advance! handles tool_use input deltas and parses partial json" do
    assistant = build_assistant
    fake_adapter = build_fake_adapter(
      events: [
        { type: :content_block_start, index: 0, block: { type: "tool_use", id: "toolu_x", name: "noop", input: {} } },
        { type: :tool_use_input_delta, index: 0, partial_json: '{"path":' },
        { type: :tool_use_input_delta, index: 0, partial_json: '"R.md"}' },
        { type: :content_block_stop, index: 0 },
        { type: :message_stop }
      ],
      usage: { prompt_tokens: 5, completion_tokens: 1, cache_read_tokens: 0, cache_creation_tokens: 0, finish_reason: "tool_use" }
    )
    assistant.define_singleton_method(:llm_adapter) { fake_adapter }
    assistant.define_singleton_method(:needs_tool_loop?) { false }  # skip tool execution for this test

    assistant.advance!
    assistant.reload

    assert_equal({ "path" => "R.md" }, assistant.content_blocks.first["input"])
    assert_equal 1, ToolCall.where(message: assistant).count
  end

  private
    def build_assistant
      chat_sessions(:one).messages.create!(role: :assistant, status: :pending, content_blocks: [], model: "claude-opus-4-7", provider: "anthropic")
    end

    def build_fake_adapter(events: [], usage: {}, raise_error: nil)
      adapter = Object.new
      adapter.define_singleton_method(:stream) do |messages:, tools:, model:, &block|
        raise raise_error if raise_error
        events.each(&block)
        usage
      end
      adapter
    end
end
