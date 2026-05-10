class ExecuteColumnJob < ApplicationJob
  queue_as :execution

  discard_on ActiveJob::DeserializationError

  def perform(run_id)
    run = Run.find_by(id: run_id)
    return unless run
    return if run.terminal?

    column = run.column
    unless column.runnable?
      run.finish!(status: :failed, error: StandardError.new("Column not runnable: missing adapter or job_spec/success_criteria"))
      return
    end

    run.start!

    prompt = column.compose_unified_prompt(task: run.task)
    session_id = run.resumable_session_id

    column.adapter_class.execute(run: run, prompt: prompt, session_id: session_id)
  rescue StandardError => e
    if run && !run.terminal?
      run.finish!(status: :failed, error: e)
      run.task&.post_system_comment(
        author: column,
        body: "My session ended without completing work. Reason: #{e.message}"
      )
    end
  end
end
