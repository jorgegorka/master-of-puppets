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
    adapter.define_singleton_method(:stream) do |messages:, tools:, model:, system: nil, &block|
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

  # A :failed tool_call already gets an is_error tool_result appended by
  # run_tool_calls! (see lines around 176-184) so the LLM can recover. Treat
  # those failures as resolved — otherwise needs_tool_loop? keeps spinning
  # until MAX_TOOL_ITERATIONS even after the model emits a clean text reply.
  test "needs_tool_loop? treats :failed tool_calls as resolved" do
    session = chat_sessions(:one)
    assistant = session.messages.create!(
      role: :assistant, status: :streaming,
      model: session.model, provider: "anthropic",
      content_blocks: [
        { "type" => "tool_use", "id" => "toolu_a", "name" => "read_file", "input" => {} },
        { "type" => "tool_use", "id" => "toolu_b", "name" => "read_file", "input" => {} },
        { "type" => "tool_use", "id" => "toolu_c", "name" => "garbage",   "input" => {} }
      ]
    )
    assistant.tool_calls.create!(provider_tool_id: "toolu_a", name: "read_file", source: :internal, status: :succeeded, input: {})
    assistant.tool_calls.create!(provider_tool_id: "toolu_b", name: "read_file", source: :internal, status: :succeeded, input: {})
    assistant.tool_calls.create!(provider_tool_id: "toolu_c", name: "garbage",   source: :unknown,  status: :failed,    input: {}, error_message: "unknown tool")

    refute assistant.send(:needs_tool_loop?),
      "failed tool_calls must be treated as resolved (the is_error tool_result is already appended)"
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

  test "available_tools includes Tool::Internal definitions" do
    msg = messages(:hello)
    names = msg.send(:available_tools).map { |d| d[:name] }
    assert_includes names, "read_file"
    assert_includes names, "write_file"
  end

  test "available_tools hides run_shell from non-admin users" do
    msg = messages(:hello)
    member_session = ChatSession.create!(user: users(:member), title: "m", model: "claude-opus-4-7", provider: "anthropic", last_active_at: Time.current)
    member_msg = member_session.messages.create!(role: :assistant, status: :pending, content_blocks: [], model: "claude-opus-4-7", provider: "anthropic")
    member_names = member_msg.send(:available_tools).map { |d| d[:name] }
    admin_names  = msg.send(:available_tools).map { |d| d[:name] }
    refute_includes member_names, "run_shell"
    assert_includes admin_names,  "run_shell"
  end

  test "build_system_prompt embeds enabled skill bodies" do
    msg = messages(:hello)
    skill = skills(:filesystem)
    skill.enable_for(msg.chat_session.user)
    # `enabled_skills` is an AR relation that loads fresh Skill rows, so stubbing
    # the fixture instance directly wouldn't be hit. Patch Skill#body globally
    # for the duration of the block instead.
    original = Skill.instance_method(:body)
    Skill.define_method(:body) { "RULES: be careful" }
    begin
      assert_includes msg.send(:build_system_prompt), "RULES: be careful"
    ensure
      Skill.define_method(:body, original)
    end
  end

  test "prompt_messages returns history only — no :system role entry" do
    msg = messages(:hello)
    skill = skills(:filesystem)
    skill.enable_for(msg.chat_session.user)
    original = Skill.instance_method(:body)
    Skill.define_method(:body) { "RULES" }
    begin
      messages = msg.send(:prompt_messages)
      refute messages.any? { |m| m[:role] == :system || m[:role] == "system" },
        "system prompt must travel via the system: kwarg, not messages[]"
    ensure
      Skill.define_method(:body, original)
    end
  end

  test "system_prompt returns the concatenated enabled skill bodies" do
    msg = messages(:hello)
    skill = skills(:filesystem)
    skill.enable_for(msg.chat_session.user)
    original = Skill.instance_method(:body)
    Skill.define_method(:body) { "RULES: be careful" }
    begin
      assert_includes msg.send(:system_prompt), "RULES: be careful"
    ensure
      Skill.define_method(:body, original)
    end
  end

  test "advance! passes system: kwarg to llm adapter" do
    session = chat_sessions(:one)
    session.messages.create!(role: :user, content_blocks: [ { type: "text", text: "hi" } ], status: :completed, model: "claude-opus-4-7", provider: "anthropic")
    assistant = session.messages.create!(role: :assistant, status: :pending, content_blocks: [], model: "claude-opus-4-7", provider: "anthropic")

    captured_kwargs = nil
    adapter = Object.new
    adapter.define_singleton_method(:stream) do |**kwargs, &block|
      captured_kwargs = kwargs
      block.call({ type: :message_stop, finish_reason: "end_turn" })
      { prompt_tokens: 1, completion_tokens: 1, cache_read_tokens: 0, cache_creation_tokens: 0, finish_reason: "end_turn" }
    end
    assistant.define_singleton_method(:llm_adapter) { adapter }

    assistant.advance!
    assert captured_kwargs.key?(:system), "system: kwarg must be passed to adapter.stream"
  end

  test "infer_source returns :internal for read_file" do
    msg = messages(:hello)
    assert_equal :internal, msg.send(:infer_source, "read_file")
  end

  test "infer_source returns :unknown for a name that matches no tool" do
    msg = messages(:hello)
    assert_equal :unknown, msg.send(:infer_source, "garbage_#{SecureRandom.hex(4)}")
  end

  test "infer_source returns :mcp for an exposed MCP tool name" do
    msg = messages(:hello)
    assert_equal :mcp, msg.send(:infer_source, mcp_tools(:context7_search).name)
  end

  test "available_tools includes Tool::Mcp definitions for the chat session's user" do
    msg = messages(:hello)
    names = msg.send(:available_tools).map { |d| d[:name] }
    assert_includes names, "search"
    assert_includes names, "fetch"
  end

  test "build_system_prompt truncates skill bodies past MAX_SKILL_BODY_BYTES" do
    msg = messages(:hello)
    skill = skills(:filesystem)
    skill.enable_for(msg.chat_session.user)
    huge = "x" * (Message::Streamable::MAX_SKILL_BODY_BYTES + 100)
    original = Skill.instance_method(:body)
    Skill.define_method(:body) { huge }
    begin
      prompt = msg.send(:build_system_prompt)
      assert_includes prompt, "[truncated]"
      assert prompt.bytesize < huge.bytesize, "long bodies must be truncated in the system prompt"
    ensure
      Skill.define_method(:body, original)
    end
  end

  test "enabled_skills is memoized across advance! iterations" do
    msg = messages(:hello)
    call_count = 0
    Skill.singleton_class.alias_method(:__real_enabled_for, :enabled_for)
    Skill.define_singleton_method(:enabled_for) do |u|
      call_count += 1
      __real_enabled_for(u)
    end
    begin
      msg.send(:enabled_skills)
      msg.send(:enabled_skills)
      assert_equal 1, call_count, "Skill.enabled_for must be called at most once per Message instance"
    ensure
      Skill.singleton_class.alias_method(:enabled_for, :__real_enabled_for)
      Skill.singleton_class.remove_method(:__real_enabled_for)
    end
  end

  test "run_tool_calls! reads tc.output['content'] from the new hash shape" do
    msg = messages(:hello)
    ToolCall.create!(
      message: msg, provider_tool_id: "toolu_x", name: "read_file",
      source: :internal, input: { "path" => "memory/x.md" },
      status: :succeeded, output: { "content" => "hello body" }
    )
    msg.send(:run_tool_calls!)
    block = msg.content_blocks.find { |b| b["type"] == "tool_result" && b["tool_use_id"] == "toolu_x" }
    refute_nil block, "expected a tool_result block appended"
    assert_equal "hello body", block["content"], "should read the content key, not Hash#to_s"
    refute block["is_error"]
  end

  test "run_tool_calls! appends an is_error tool_result for failed tool calls" do
    msg = messages(:hello)
    ToolCall.create!(
      message: msg, provider_tool_id: "toolu_bad", name: "read_file",
      source: :internal, input: { "path" => "missing" },
      status: :failed, error_message: "not found"
    )
    msg.send(:run_tool_calls!)
    block = msg.content_blocks.find { |b| b["type"] == "tool_result" && b["tool_use_id"] == "toolu_bad" }
    refute_nil block
    assert_equal "not found", block["content"]
    assert block["is_error"]
  end

  private
    def build_assistant
      chat_sessions(:one).messages.create!(role: :assistant, status: :pending, content_blocks: [], model: "claude-opus-4-7", provider: "anthropic")
    end

    def build_fake_adapter(events: [], usage: {}, raise_error: nil)
      adapter = Object.new
      adapter.define_singleton_method(:stream) do |messages:, tools:, model:, system: nil, &block|
        raise raise_error if raise_error
        events.each(&block)
        usage
      end
      adapter
    end
end
