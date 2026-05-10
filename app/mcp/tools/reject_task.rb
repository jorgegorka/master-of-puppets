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
      perform_transition(
        task_id: arguments["task_id"],
        kind: :reject,
        feedback: arguments["feedback"],
        target_column_name: arguments["to_column_name"]
      )
    end
  end
end
