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
      perform_transition(
        task_id: arguments["task_id"],
        kind: :block,
        reason: arguments["reason"]
      )
    end
  end
end
