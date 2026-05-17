module ScheduledJob::Runnable
  extend ActiveSupport::Concern

  MAX_OUTPUT_BYTES = 256 * 1024

  def run_now(now: Time.current)
    return if paused?

    run = nil
    transaction do
      run = runs.create!(status: :running, started_at: now)
      chat = create_run_chat_session(run)
      run.update!(chat_session: chat)
      track_event :run_started, job_run_id: run.id, chat_session_id: chat.id
    end

    begin
      chat = run.chat_session
      drive_assistant(chat)
      capture_success(run, chat)
    rescue StandardError => e
      capture_failure(run, e)
    end

    advance_schedule(now)
    run
  end

  def run_later
    ScheduledJob::RunnerJob.perform_later(self)
  end

  private
    def create_run_chat_session(run)
      ChatSession.create!(
        user:           user,
        title:          "Job: #{name} (#{run.created_at.utc.iso8601})",
        model:          model,
        provider:       provider,
        last_active_at: Time.current
      )
    end

    def drive_assistant(chat)
      chat.messages.create!(
        role:           :user,
        status:         :completed,
        content_blocks: [ { type: "text", text: prompt } ],
        model:          model,
        provider:       provider
      )
      assistant = chat.messages.create!(
        role:           :assistant,
        status:         :pending,
        content_blocks: [],
        model:          model,
        provider:       provider
      )
      assistant.advance!
    end

    def capture_success(run, chat)
      assistant      = chat.messages.where(role: :assistant).order(:created_at).last
      text           = extract_text_output(assistant)
      original_bytes = text.to_s.bytesize
      truncated      = original_bytes > MAX_OUTPUT_BYTES
      cost           = assistant.cost_usd || assistant.compute_cost

      transaction do
        run.update!(
          status:                    :succeeded,
          finished_at:               Time.current,
          output:                    truncate_output(text),
          output_truncated_at_bytes: truncated ? original_bytes : nil,
          prompt_tokens:             assistant.prompt_tokens,
          completion_tokens:         assistant.completion_tokens,
          cache_read_tokens:         assistant.cache_read_tokens,
          cache_creation_tokens:     assistant.cache_creation_tokens,
          cost_usd:                  cost
        )
        track_event :run_succeeded,
                    job_run_id: run.id,
                    cost_usd:   run.cost_usd.to_s,
                    tokens:     run.prompt_tokens.to_i + run.completion_tokens.to_i
      end
    end

    def extract_text_output(assistant)
      Array(assistant.content_blocks).filter_map { |b|
        b["text"] if b.is_a?(Hash) && b["type"] == "text"
      }.join("\n\n")
    end

    def truncate_output(text)
      return text if text.to_s.bytesize <= MAX_OUTPUT_BYTES

      head     = text.byteslice(0, MAX_OUTPUT_BYTES).to_s.scrub
      overflow = text.bytesize - MAX_OUTPUT_BYTES
      "#{head}\n…[truncated #{overflow} bytes]"
    end

    def capture_failure(run, error)
      transaction do
        run.update!(status: :failed, finished_at: Time.current, error_message: error.message)
        track_event :run_failed,
                    job_run_id:    run.id,
                    error_class:   error.class.name,
                    error_message: error.message
      end
    end

    def advance_schedule(now)
      update!(last_run_at: now, next_run_at: compute_next_run_at(from: now))
    end
end
