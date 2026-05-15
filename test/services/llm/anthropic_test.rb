require "test_helper"
require "ostruct"

# We stub the SDK at the @client.messages.stream level rather than recording a
# VCR cassette, because cassette recording requires a real ANTHROPIC_API_KEY.
# When credentials are available, set ANTHROPIC_API_KEY and switch to VCR-based
# replay; the contract verified here is the same.
module Llm
  class AnthropicTest < ActiveSupport::TestCase
    setup do
      # Hand-craft a minimal API key on the fixture so the adapter constructs.
      provider_configs(:anthropic).update!(api_key: "test-key")
      @adapter = Llm::Anthropic.new(provider_configs(:anthropic))
    end

    test "stream yields normalized text deltas and returns usage" do
      fake_message = OpenStruct.new(
        id: "msg_test",
        model: "claude-opus-4-7",
        stop_reason: "end_turn",
        usage: OpenStruct.new(
          input_tokens: 10,
          output_tokens: 5,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0
        )
      )

      raw_events = [
        OpenStruct.new(type: :message_start, message: fake_message),
        OpenStruct.new(type: :content_block_start, index: 0,
                       content_block: OpenStruct.new(to_h: { type: "text", text: "" })),
        OpenStruct.new(type: :content_block_delta, index: 0,
                       delta: OpenStruct.new(type: :text_delta, text: "Hi")),
        OpenStruct.new(type: :content_block_delta, index: 0,
                       delta: OpenStruct.new(type: :text_delta, text: " there")),
        OpenStruct.new(type: :content_block_stop, index: 0),
        OpenStruct.new(type: :message_delta, delta: OpenStruct.new(stop_reason: "end_turn")),
        OpenStruct.new(type: :message_stop)
      ]

      fake_stream = FakeStream.new(raw_events, fake_message)
      @adapter.instance_variable_get(:@client).messages.define_singleton_method(:stream) do |_|
        fake_stream
      end

      received = []
      usage = @adapter.stream(messages: [ { role: "user", content: "hi" } ], tools: [], model: "claude-opus-4-7") do |event|
        received << event
      end

      types = received.map { _1[:type] }
      assert_includes types, :message_start
      assert_includes types, :content_block_start
      assert_includes types, :text_delta
      assert_includes types, :content_block_stop
      assert_includes types, :message_stop

      text_deltas = received.select { _1[:type] == :text_delta }
      assert_equal "Hi there", text_deltas.map { _1[:text] }.join

      assert_equal 10, usage[:prompt_tokens]
      assert_equal 5,  usage[:completion_tokens]
      assert_equal "end_turn", usage[:finish_reason]
    end

    test "stream normalizes thinking deltas" do
      fake_message = build_fake_message
      raw_events = [
        OpenStruct.new(type: :content_block_start, index: 0,
                       content_block: OpenStruct.new(to_h: { type: "thinking", thinking: "" })),
        OpenStruct.new(type: :content_block_delta, index: 0,
                       delta: OpenStruct.new(type: :thinking_delta, thinking: "Let me think.")),
        OpenStruct.new(type: :content_block_stop, index: 0),
        OpenStruct.new(type: :message_stop)
      ]

      fake_stream = FakeStream.new(raw_events, fake_message)
      @adapter.instance_variable_get(:@client).messages.define_singleton_method(:stream) do |_|
        fake_stream
      end

      received = []
      @adapter.stream(messages: [], tools: [], model: "x") { received << _1 }

      thinking = received.find { _1[:type] == :thinking_delta }
      assert_equal "Let me think.", thinking[:thinking]
    end

    test "stream normalizes tool_use input deltas" do
      fake_message = build_fake_message
      raw_events = [
        OpenStruct.new(type: :content_block_start, index: 0,
                       content_block: OpenStruct.new(to_h: { type: "tool_use", id: "toolu_x", name: "read_file", input: {} })),
        OpenStruct.new(type: :content_block_delta, index: 0,
                       delta: OpenStruct.new(type: :input_json_delta, partial_json: '{"path":')),
        OpenStruct.new(type: :content_block_delta, index: 0,
                       delta: OpenStruct.new(type: :input_json_delta, partial_json: '"R.md"}')),
        OpenStruct.new(type: :content_block_stop, index: 0),
        OpenStruct.new(type: :message_stop)
      ]

      fake_stream = FakeStream.new(raw_events, fake_message)
      @adapter.instance_variable_get(:@client).messages.define_singleton_method(:stream) do |_|
        fake_stream
      end

      received = []
      @adapter.stream(messages: [], tools: [], model: "x") { received << _1 }

      partials = received.select { _1[:type] == :tool_use_input_delta }.map { _1[:partial_json] }
      assert_equal '{"path":"R.md"}', partials.join
    end

    private
      def build_fake_message
        OpenStruct.new(
          id: "msg_test",
          model: "claude-opus-4-7",
          stop_reason: "end_turn",
          usage: OpenStruct.new(
            input_tokens: 1,
            output_tokens: 1,
            cache_read_input_tokens: 0,
            cache_creation_input_tokens: 0
          )
        )
      end

      class FakeStream
        def initialize(events, accumulated_message)
          @events = events
          @accumulated_message = accumulated_message
        end

        def each(&block)
          @events.each(&block)
        end

        def accumulated_message
          @accumulated_message
        end
      end
  end
end
