module Tools
  class CreateTask < BaseTool
    def name
      "create_task"
    end

    def definition
      {
        name: name,
        description: "Create a new task in the project, optionally as a subtask, and optionally targeted at a specific column.",
        inputSchema: {
          type: "object",
          properties: {
            title: { type: "string" },
            description: { type: "string" },
            priority: { type: "string", enum: %w[low medium high urgent] },
            parent_task_id: { type: "integer" },
            target_column_name: { type: "string", description: "Optional: column the new task should land in. Defaults to project's first non-terminal column." }
          },
          required: %w[title]
        }
      }
    end

    def call(arguments)
      target_column = if arguments["target_column_name"].present?
                        project.columns.where("LOWER(name) = ?", arguments["target_column_name"].to_s.downcase).first
      else
                        project.columns.non_terminal.ordered.first
      end

      raise ArgumentError, "No suitable target column" unless target_column

      task = project.tasks.new(
        title: arguments["title"],
        description: arguments["description"],
        priority: arguments["priority"] || "medium",
        creator: creator_user,
        column: target_column,
        parent_task_id: arguments["parent_task_id"],
        entered_column_at: Time.current
      )

      task.save!

      { id: task.id, title: task.title, column: target_column.name }
    end

    private

    def creator_user
      run = column.runs.where.not(initiating_user_id: nil).order(:created_at).last
      run&.initiating_user || project.memberships.where(role: :owner).first&.user || project.memberships.first&.user
    end
  end
end
