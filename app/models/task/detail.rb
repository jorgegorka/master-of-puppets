class Task::Detail
  attr_reader :task

  def initialize(task)
    @task = task
  end

  def messages
    @messages ||= task.messages.includes(:author, replies: :author).roots.chronological
  end

  def document_links
    @document_links ||= task.task_documents.joins(:document).includes(:document).order("documents.title")
  end

  def any_documents?
    document_links.any?
  end

  def timeline_entries(before: nil)
    Timeline.new(sources: timeline_sources, before: before)
  end

  private

  def timeline_sources
    [
      task.messages.roots.includes(:author, replies: :author),
      task.audit_events.includes(:actor),
      task.task_evaluations.includes(:root_task)
    ]
  end
end
