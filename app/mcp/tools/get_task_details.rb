module Tools
  class GetTaskDetails < BaseTool
    def name
      "get_task_details"
    end

    def definition
      {
        name: name,
        description: "Get full details of a task including messages and subtasks.",
        inputSchema: {
          type: "object",
          properties: {
            task_id: { type: "integer" }
          },
          required: [ "task_id" ]
        }
      }
    end

    def call(arguments)
      task = project.tasks.find(arguments["task_id"])

      messages = task.messages.includes(:author).chronological.map do |msg|
        author_label = case msg.author
        when Column then msg.author.name
        when User   then msg.author.email_address
        else msg.author_type
        end
        {
          id: msg.id,
          author: author_label,
          author_type: msg.author_type,
          body: msg.body,
          message_type: msg.message_type,
          created_at: msg.created_at.iso8601
        }
      end

      subtasks = task.subtasks.includes(:column).map do |st|
        { id: st.id, title: st.title, column: st.column&.name, completion_percentage: st.completion_percentage }
      end

      {
        id: task.id,
        title: task.title,
        description: task.description,
        summary: task.summary,
        priority: task.priority,
        creator_user_id: task.creator_user_id,
        column: task.column&.name,
        column_id: task.column_id,
        parent_task_id: task.parent_task_id,
        completion_percentage: task.completion_percentage,
        reviewer_id: task.reviewed_by_user_id,
        reviewed_at: task.reviewed_at&.iso8601,
        cost_cents: task.cost_cents,
        created_at: task.created_at.iso8601,
        messages: messages,
        subtasks: subtasks
      }
    end
  end
end
