module Tools
  class AdvanceTask < BaseTool
    def name
      "advance_task"
    end

    def definition
      {
        name: name,
        description: "Advance a task from this column to the next column. Use when the column's success criteria are met.",
        inputSchema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "ID of the task to advance" },
            reason: { type: "string", description: "Brief reason the task is ready to advance" },
            to_column_name: { type: "string", description: "Optional: name of a target column. Defaults to next column by position." }
          },
          required: %w[task_id reason]
        }
      }
    end

    def call(arguments)
      task = project.tasks.find(arguments["task_id"])
      run = active_run_for(task)
      raise ArgumentError, "No active run for this column on task #{task.id}" unless run

      transition = Columns::Transition.new(
        task: task,
        actor: run,
        kind: :advance,
        reason: arguments["reason"],
        target_column_name: arguments["to_column_name"]
      )
      raise ArgumentError, transition.errors.full_messages.to_sentence unless transition.valid?

      task.enter_column!(transition.target_column, actor: run, kind: :advance, reason: arguments["reason"])

      { status: "ok", task_id: task.id, to_column: transition.target_column.name }
    end
  end
end
