module Tools
  class RejectTask < BaseTool
    def name
      "reject_task"
    end

    def definition
      {
        name: name,
        description: "Send a task back to a previous column with feedback when it does not meet this column's criteria.",
        inputSchema: {
          type: "object",
          properties: {
            task_id: { type: "integer" },
            feedback: { type: "string", description: "Required feedback explaining why the task was rejected" },
            to_column_name: { type: "string", description: "Optional: name of a target column. Defaults to previous non-terminal column." }
          },
          required: %w[task_id feedback]
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
        kind: :reject,
        feedback: arguments["feedback"],
        target_column_name: arguments["to_column_name"]
      )
      raise ArgumentError, transition.errors.full_messages.to_sentence unless transition.valid?

      task.enter_column!(transition.target_column, actor: run, kind: :reject, feedback: arguments["feedback"])

      { status: "ok", task_id: task.id, to_column: transition.target_column.name }
    end
  end
end
