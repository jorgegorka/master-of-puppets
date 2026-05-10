class Dashboard::AttentionItems
  attr_reader :project

  def initialize(project)
    @project = project
  end

  def tasks_pending_review
    @tasks_pending_review ||= project.tasks.pending_human_review
      .includes(:column, :creator, :parent_task)
      .order(updated_at: :desc)
  end

  def blocked_tasks
    @blocked_tasks ||= project.tasks.blocked
      .includes(:column, :parent_task)
      .order(updated_at: :desc)
  end

  def total_count
    tasks_pending_review.size + blocked_tasks.size
  end

  def any?
    tasks_pending_review.any? || blocked_tasks.any?
  end

  def broadcast_to(project_id)
    if any?
      Turbo::StreamsChannel.broadcast_update_to(
        "dashboard_project_#{project_id}",
        target: "dashboard-attention",
        partial: "dashboard/attention_section",
        locals: { attention: self }
      )
    else
      Turbo::StreamsChannel.broadcast_update_to(
        "dashboard_project_#{project_id}",
        target: "dashboard-attention",
        html: ""
      )
    end
  end
end
