module Tools
  class ListMyTasks < BaseTool
    def name
      "list_my_tasks"
    end

    def definition
      {
        name: name,
        description: "List tasks currently in this column.",
        inputSchema: {
          type: "object",
          properties: {}
        }
      }
    end

    def call(arguments)
      tasks = column.tasks.order(:position).map do |task|
        {
          id: task.id,
          title: task.title,
          description: task.description,
          priority: task.priority,
          parent_task_id: task.parent_task_id,
          completion_percentage: task.completion_percentage,
          creator_id: task.creator_user_id
        }
      end

      { tasks: tasks, count: tasks.size }
    end
  end
end
