module Tools
  class ListColumns < BaseTool
    def name
      "list_columns"
    end

    def definition
      {
        name: name,
        description: "List every column on this project's board, in board order. Use this to discover where to advance/reject tasks to and to look up a column's id by name.",
        inputSchema: {
          type: "object",
          properties: {}
        }
      }
    end

    def call(_arguments)
      counts = project.tasks.group(:column_id).count
      columns = project.columns.ordered.map { |col| column_payload(col, task_count: counts.fetch(col.id, 0)) }
      { columns: columns, count: columns.size }
    end
  end
end
