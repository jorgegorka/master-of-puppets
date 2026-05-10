module Tools
  class FindColumn < BaseTool
    def name
      "find_column"
    end

    def definition
      {
        name: name,
        description: "Look up a single column on this project's board by exact name (case-insensitive) or by id. Returns nil-friendly metadata so you can resolve column references before transitioning a task.",
        inputSchema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Column name (case-insensitive exact match)." },
            id:   { type: "integer", description: "Column id." }
          }
        }
      }
    end

    def call(arguments)
      raise ArgumentError, "Provide either name or id" if arguments["name"].blank? && arguments["id"].blank?

      col = arguments["id"].present? ? project.columns.find_by(id: arguments["id"]) : project.columns.by_name_ci(arguments["name"]).first
      return { found: false } unless col

      column_payload(col, task_count: col.tasks.count).merge(found: true, description: col.description)
    end
  end
end
