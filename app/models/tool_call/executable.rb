module ToolCall::Executable
  extend ActiveSupport::Concern

  class UnsupportedSource < StandardError; end

  def execute
    raise "tool_call already #{status}" unless pending?

    run_with_failure_capture
    self
  end

  private
    # The pending? guard above must NOT be caught by this rescue — calling
    # execute a second time on a :succeeded row would otherwise overwrite
    # the succeeded state with :failed before re-raising. Keep the rescue
    # scoped to the actual dispatch + persistence block.
    def run_with_failure_capture
      transaction do
        update!(status: :running, started_at: Time.current)
        track_event :invoked, source: source, name: name
      end

      result =
        case source.to_sym
        when :internal
          Tool::Internal.invoke(name: name, input: input.to_h, user: message.chat_session.user)
        when :mcp, :skill
          Tool::Result.failure("#{source} tool execution lands in Phase 4/6")
        when :unknown
          Tool::Result.failure("unknown tool: #{name}")
        else
          raise UnsupportedSource, source
        end

      transaction do
        update!(
          status:        result.is_error ? :failed : :succeeded,
          finished_at:   Time.current,
          output:        result.is_error ? nil : { content: result.output },
          error_message: result.is_error ? result.error : nil
        )
        track_event(result.is_error ? :failed : :succeeded,
          name: name,
          duration_ms: ((finished_at - started_at) * 1000).to_i)
      end
    rescue => e
      update!(status: :failed, finished_at: Time.current, error_message: "#{e.class}: #{e.message}")
      track_event :failed, name: name, error_class: e.class.name
      raise
    end
end
