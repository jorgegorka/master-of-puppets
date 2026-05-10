module Tools
  class BlockTask < BaseTool
    def name
      "block_task"
    end

    def definition
      {
        name: name,
        description: "Flag a task as blocked when you cannot proceed (missing info, external dependency, etc).",
        inputSchema: {
          type: "object",
          properties: {
            task_id: { type: "integer" },
            reason: { type: "string", description: "What is blocking progress" }
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
        kind: :block,
        reason: arguments["reason"]
      )
      raise ArgumentError, transition.errors.full_messages.to_sentence unless transition.valid?

      task.enter_column!(transition.target_column, actor: run, kind: :block, reason: arguments["reason"])

      { status: "ok", task_id: task.id, to_column: transition.target_column.name }
    end
  end
end
