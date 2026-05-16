module Message::Streamable
  extend ActiveSupport::Concern

  MAX_TOOL_ITERATIONS = 10
  # Cap on a single skill body in the system prompt. A 5 MB skill would
  # otherwise blow past the provider's context window and 400 every call.
  MAX_SKILL_BODY_BYTES = 64_000

  def advance!(iteration: 1)
    raise Llm::ToolLoopExceeded, "exceeded #{MAX_TOOL_ITERATIONS} tool iterations" if iteration > MAX_TOOL_ITERATIONS

    transition_to_streaming!

    usage = llm_adapter.stream(
      messages: prompt_messages,
      tools:    available_tools,
      model:    model,
      system:   system_prompt
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

    def infer_source(name)
      return :internal if Tool::Internal.lookup(name)
      :unknown
    end

    def broadcast_event(event)
      ChatChannel.broadcast_to(chat_session, event) if defined?(ChatChannel)
    end

    def prompt_messages
      chat_session.messages.ordered.where("messages.id <= ?", id).map do |m|
        { role: m.role, content: m.content_blocks }
      end
    end

    def system_prompt
      build_system_prompt
    end

    def build_system_prompt
      enabled_skills.map { |s| "## Skill: #{s.name}\n\n#{truncate_skill_body(s.body)}" }.join("\n\n")
    end

    def truncate_skill_body(body)
      return body if body.to_s.bytesize <= MAX_SKILL_BODY_BYTES
      body.to_s.byteslice(0, MAX_SKILL_BODY_BYTES).to_s.scrub + "\n…[truncated]"
    end

    # Broader per-user / per-skill tool filtering lands with Phase 6 + the
    # `agent_profile_skills` join. Until then `run_shell` is hidden from
    # non-admins so it doesn't even appear as an option in the tool list.
    def available_tools
      defs = Tool::Internal.all_definitions
      defs = defs.reject { |d| d[:name] == "run_shell" } unless chat_session.user&.admin?
      defs + enabled_skills.flat_map { |s| skill_tool_definitions(s) }
    end

    def enabled_skills
      @enabled_skills ||= Skill.enabled_for(chat_session.user).to_a
    end

    def skill_tool_definitions(_skill)
      # Phase 3 wires Tool::Internal only. Skills inject prompt sections (see
      # build_system_prompt above) but their per-skill tool-def arrays land in
      # Phase 6 alongside the agent profile work. Return [] now to keep the
      # surface area honest.
      []
    end

    def needs_tool_loop?
      pending_ids = content_blocks.filter_map { |b| b["id"] if b.is_a?(Hash) && b["type"] == "tool_use" }
      return false if pending_ids.empty?
      # :failed counts as resolved — run_tool_calls! appends an is_error
      # tool_result for those so the LLM can recover. Otherwise a single
      # failed call would keep the loop alive until MAX_TOOL_ITERATIONS.
      resolved_ids = tool_calls.where(provider_tool_id: pending_ids, status: %i[succeeded failed]).pluck(:provider_tool_id).to_set
      pending_ids.any? { |id| !resolved_ids.include?(id) }
    end

    def run_tool_calls!
      tool_calls.where(status: :pending).find_each(&:execute)
      tool_calls.where(status: :succeeded).find_each do |tc|
        next if content_blocks.any? { |b| b.is_a?(Hash) && b["type"] == "tool_result" && b["tool_use_id"] == tc.provider_tool_id }
        self.content_blocks << {
          "type"        => "tool_result",
          "tool_use_id" => tc.provider_tool_id,
          "content"     => tc.output.is_a?(Hash) ? tc.output["content"].to_s : tc.output.to_s,
          "is_error"    => false
        }
      end
      # Also append a failed tool_result for any tool_calls that failed, so the
      # LLM sees the error and can decide what to do next.
      tool_calls.where(status: :failed).find_each do |tc|
        next if content_blocks.any? { |b| b.is_a?(Hash) && b["type"] == "tool_result" && b["tool_use_id"] == tc.provider_tool_id }
        self.content_blocks << {
          "type"        => "tool_result",
          "tool_use_id" => tc.provider_tool_id,
          "content"     => tc.error_message.to_s,
          "is_error"    => true
        }
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
