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

  # Review issue #2 — rate-limit retry must drop half-streamed tool_use blocks
  # (those with input_partial still present) so the retried prompt isn't
  # malformed when shipped back to the provider.
  test "advance! drops half-streamed tool_use blocks before retry" do
    session = chat_sessions(:one)
    assistant = session.messages.create!(
      role: :assistant,
      status: :rate_limited,
      model: session.model,
      provider: "anthropic",
      content_blocks: [
        { "type" => "text",     "text" => "let me check" },
        { "type" => "tool_use", "id" => "toolu_abc", "name" => "read_file", "input_partial" => '{"pa' }
      ]
    )
    fake_adapter = build_fake_adapter(
      events: [ { type: :message_stop, finish_reason: "end_turn" } ],
      usage:  { prompt_tokens: 1, completion_tokens: 1, cache_read_tokens: 0, cache_creation_tokens: 0, finish_reason: "end_turn" }
    )
    assistant.define_singleton_method(:llm_adapter) { fake_adapter }

    assistant.advance!
    assistant.reload

    refute assistant.content_blocks.any? { |b| b["type"] == "tool_use" && b.key?("input_partial") },
      "half-streamed tool_use must be dropped on retry"
  end

  # Review issue #1 — a tool that never reaches :succeeded would otherwise loop
  # forever inside advance!. MAX_TOOL_ITERATIONS caps the recursion; failure
  # ends in the :failed branch (re-raised by the generic rescue).
  test "advance! raises Llm::ToolLoopExceeded past MAX_TOOL_ITERATIONS" do
    assistant = build_assistant
    fake_adapter = build_fake_adapter(
      events: [ { type: :message_stop, finish_reason: "tool_use" } ],
      usage:  { prompt_tokens: 0, completion_tokens: 0, cache_read_tokens: 0, cache_creation_tokens: 0, finish_reason: "tool_use" }
    )
    assistant.define_singleton_method(:llm_adapter)      { fake_adapter }
    assistant.define_singleton_method(:needs_tool_loop?) { true }
    assistant.define_singleton_method(:run_tool_calls!)  { nil }

    assert_raises(Llm::ToolLoopExceeded) { assistant.advance! }
    assert_equal "failed", assistant.reload.status
  end

  # Review issue #6 — exercises the full recursive arm: first stream emits a
  # tool_use, the loop runs run_tool_calls!, the tool succeeds and a tool_result
  # is appended, and the second stream finalizes with text. Without this end-to-
  # end test, fixes #1 and #2 are unverifiable.
  test "advance! completes a tool-call round trip" do
    session = chat_sessions(:one)
    session.messages.create!(role: :user, content_blocks: [ { type: "text", text: "read R.md" } ], status: :completed, model: session.model, provider: "anthropic")
    assistant = session.messages.create!(role: :assistant, status: :pending, content_blocks: [], model: session.model, provider: "anthropic")

    turn1 = [
      { type: :content_block_start, index: 0, block: { type: "tool_use", id: "toolu_rt", name: "read_file", input: {} } },
      { type: :tool_use_input_delta, index: 0, partial_json: '{"path":"R.md"}' },
      { type: :content_block_stop, index: 0 },
      { type: :message_stop, finish_reason: "tool_use" }
    ]
    # Indices in turn 2 sit past the existing tool_use(0) + tool_result(1) blocks.
    # apply_stream_event! writes by absolute index into content_blocks, so the
    # second turn must continue numbering rather than restart at 0.
    turn2 = [
      { type: :content_block_start, index: 2, block: { type: "text", text: "" } },
      { type: :text_delta, index: 2, text: "done" },
      { type: :content_block_stop, index: 2 },
      { type: :message_stop, finish_reason: "end_turn" }
    ]
    usage = { prompt_tokens: 5, completion_tokens: 3, cache_read_tokens: 0, cache_creation_tokens: 0, finish_reason: "end_turn" }

    call_count = 0
    adapter = Object.new
    adapter.define_singleton_method(:stream) do |messages:, tools:, model:, &block|
      events = call_count.zero? ? turn1 : turn2
      call_count += 1
      events.each(&block)
      usage
    end
    assistant.define_singleton_method(:llm_adapter) { adapter }

    # Phase 1 has no real tool registry; flip the tool_call to succeeded in-place
    # so the loop appends the tool_result block and the second stream can finalize.
    ToolCall.class_eval do
      def execute
        update!(status: :succeeded, output: { "result" => "ok" }, finished_at: Time.current)
      end
    end

    assistant.advance!
    assistant.reload

    assert_equal "completed", assistant.status
    assert_equal 2, call_count, "expected stream to be called twice (initial + post-tool-result)"
    assert assistant.tool_calls.where(name: "read_file", status: :succeeded).exists?
    assert assistant.content_blocks.any? { |b| b["type"] == "tool_result" && b["tool_use_id"] == "toolu_rt" }
  ensure
    # Restore the stub so other tests see the original NotImplementedError raiser.
    ToolCall.class_eval { remove_method(:execute) if method_defined?(:execute) }
    ToolCall.include(ToolCall::Executable)
  end

  # Review-follow-up — needs_tool_loop? used to fire one exists? query per
  # tool_use block. Collapse it into one pluck-then-set check.
  test "needs_tool_loop? checks all tool_use blocks in a single query" do
    session = chat_sessions(:one)
    assistant = session.messages.create!(
      role: :assistant, status: :streaming,
      model: session.model, provider: "anthropic",
      content_blocks: [
        { "type" => "tool_use", "id" => "toolu_1", "name" => "read_file", "input" => {} },
        { "type" => "tool_use", "id" => "toolu_2", "name" => "read_file", "input" => {} },
        { "type" => "tool_use", "id" => "toolu_3", "name" => "read_file", "input" => {} }
      ]
    )
    %w[toolu_1 toolu_2].each do |id|
      assistant.tool_calls.create!(provider_tool_id: id, name: "read_file", source: :internal, status: :succeeded, input: {})
    end
    # toolu_3 has no ToolCall row yet — so we still need the loop.
    assert_queries_count(1) do
      assert assistant.send(:needs_tool_loop?)
    end

    assistant.tool_calls.create!(provider_tool_id: "toolu_3", name: "read_file", source: :internal, status: :succeeded, input: {})
    assert_queries_count(1) do
      refute assistant.send(:needs_tool_loop?)
    end
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
