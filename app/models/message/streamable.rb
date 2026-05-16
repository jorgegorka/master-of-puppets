module Message::Streamable
  extend ActiveSupport::Concern

  MAX_TOOL_ITERATIONS = 10

  def advance!(iteration: 1)
    raise Llm::ToolLoopExceeded, "exceeded #{MAX_TOOL_ITERATIONS} tool iterations" if iteration > MAX_TOOL_ITERATIONS

    transition_to_streaming!

    usage = llm_adapter.stream(
      messages: prompt_messages,
      tools:    available_tools,
      model:    model
    ) do |event|
      apply_stream_event!(event)
      broadcast_event(event)
    end

    if needs_tool_loop?
      run_tool_calls!
      advance!(iteration: iteration + 1)
    else
      finalize!(usage)
    end
  rescue Llm::RateLimited => e
    update!(status: :rate_limited, error_message: e.message)
    Message::AdvanceJob.set(wait: e.retry_after.seconds).perform_later(self)
  rescue => e
    update!(status: :failed, error_message: e.message)
    track_event :failed, error_class: e.class.name, error_message: e.message
    raise
  end

  def advance_later
    Message::AdvanceJob.perform_later(self)
  end

  private
    def llm_adapter
      Llm::Client.for(provider: provider)
    end

    # On a rate-limit retry, content_blocks may still hold half-streamed tool_use
    # blocks (with input_partial) from the prior attempt. Shipping them back to
    # the provider yields a malformed tool_use — drop them before the next call.
    def transition_to_streaming!
      transaction do
        update!(status: :streaming) unless streaming?
        self.content_blocks = retain_completed_blocks(content_blocks)
        self.stream_cursor  = { "block_index" => -1, "byte_offset" => 0, "last_event_at" => Time.current.iso8601 }
        save!
      end
    end

    def retain_completed_blocks(blocks)
      Array(blocks).reject { |b| b.is_a?(Hash) && b["type"] == "tool_use" && b.key?("input_partial") }
    end

    def apply_stream_event!(event)
      case event[:type]
      when :content_block_start
        ensure_block_index!(event[:index])
        content_blocks[event[:index]] = event[:block].deep_stringify_keys
      when :text_delta
        block = content_blocks[event[:index]] ||= { "type" => "text", "text" => "" }
        block["text"] = block["text"].to_s + event[:text].to_s
      when :thinking_delta
        block = content_blocks[event[:index]] ||= { "type" => "thinking", "thinking" => "" }
        block["thinking"] = block["thinking"].to_s + event[:thinking].to_s
      when :tool_use_input_delta
        block = content_blocks[event[:index]] ||= { "type" => "tool_use", "input_partial" => "" }
        block["input_partial"] = block["input_partial"].to_s + event[:partial_json].to_s
      when :content_block_stop
        finalize_block!(event[:index])
      end
      self.stream_cursor = {
        "block_index"   => event[:index] || stream_cursor.to_h["block_index"],
        "byte_offset"   => 0,
        "last_event_at" => Time.current.iso8601
      }
      save!
    end

    def ensure_block_index!(index)
      return if index.nil? || index < content_blocks.size
      (content_blocks.size..index).each { |_| content_blocks << nil }
    end

    def finalize_block!(index)
      block = content_blocks[index]
      return unless block.is_a?(Hash) && block["type"] == "tool_use" && block["input_partial"]
      block["input"] = JSON.parse(block["input_partial"])
      block.delete("input_partial")
      ToolCall.find_or_create_by!(message: self, provider_tool_id: block["id"]) do |tc|
        tc.name   = block["name"]
        tc.source = infer_source(block["name"])
        tc.input  = block["input"]
        tc.status = :pending
      end
    end

    def infer_source(_name)
      # Phase 3 wires Tool::Internal and McpTool lookup. For Phase 1, default to :internal.
      :internal
    end

    def broadcast_event(event)
      ChatChannel.broadcast_to(chat_session, event) if defined?(ChatChannel)
    end

    def prompt_messages
      chat_session.messages.ordered.where("messages.id <= ?", id).map do |m|
        { role: m.role, content: m.content_blocks }
      end
    end

    def available_tools
      # Phase 3 populates this from enabled skills, Mcp tools, and built-in tools.
      []
    end

    def needs_tool_loop?
      pending_ids = content_blocks.filter_map { |b| b["id"] if b.is_a?(Hash) && b["type"] == "tool_use" }
      return false if pending_ids.empty?
      succeeded_ids = tool_calls.where(provider_tool_id: pending_ids, status: :succeeded).pluck(:provider_tool_id).to_set
      pending_ids.any? { |id| !succeeded_ids.include?(id) }
    end

    def run_tool_calls!
      tool_calls.where(status: :pending).find_each(&:execute)
      tool_calls.where(status: :succeeded).find_each do |tc|
        if content_blocks.none? { |b| b.is_a?(Hash) && b["type"] == "tool_result" && b["tool_use_id"] == tc.provider_tool_id }
          self.content_blocks << {
            "type"        => "tool_result",
            "tool_use_id" => tc.provider_tool_id,
            "content"     => tc.output.to_s,
            "is_error"    => false
          }
        end
      end
      save!
    end

    def finalize!(usage)
      self.prompt_tokens         = usage[:prompt_tokens]
      self.completion_tokens     = usage[:completion_tokens]
      self.cache_read_tokens     = usage[:cache_read_tokens]
      self.cache_creation_tokens = usage[:cache_creation_tokens]
      self.cost_usd              = compute_cost
      self.status                = :completed
      transaction do
        save!
        track_event :completed, finish_reason: usage[:finish_reason]
      end
    end

end
