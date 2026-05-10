module Tools
  class AddMessage < BaseTool
    def name
      "add_message"
    end

    def definition
      {
        name: name,
        description: "Post a message (comment or question) to a task's thread.",
        inputSchema: {
          type: "object",
          properties: {
            task_id: { type: "integer" },
            message: { type: "string" },
            message_type: { type: "string", enum: %w[comment question] }
          },
          required: %w[task_id message]
        }
      }
    end

    def call(arguments)
      task = project.tasks.find(arguments["task_id"])
      run = active_run_for(task)

      message = task.messages.create!(
        author: column,
        body: arguments["message"],
        message_type: arguments["message_type"] || "comment",
        column: column,
        run: run
      )

      { id: message.id, task_id: task.id, message_type: message.message_type }
    end
  end
end
