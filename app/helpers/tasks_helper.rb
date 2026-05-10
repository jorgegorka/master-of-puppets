module TasksHelper
  def task_column_badge(task)
    return "" unless task.column
    css_class = "kanban__column-tag kanban__column-tag--#{task.column.transition_policy}"
    tag.span(task.column.name, class: css_class)
  end

  def task_priority_badge(task)
    css_class = "priority-badge priority-badge--#{task.priority}"
    tag.span(task.priority.humanize, class: css_class)
  end

  def options_for_task_priority
    Task.priorities.keys.map { |p| [ p.humanize, p ] }
  end

  def options_for_column_select
    Current.project.columns.ordered.pluck(:name, :id)
  end

  def options_for_parent_task_select(task)
    scope = Current.project.tasks
    if task.persisted?
      excluded = [ task.id ] + task.descendant_ids
      scope = scope.where.not(id: excluded)
    end
    scope.order(:title).pluck(:title, :id)
  end

  TASK_PILL_ICONS = {
    creator:     '<svg viewBox="0 0 20 20" fill="currentColor"><path d="M3 15l1.4-8 3.6 2.6L10 4l2 5.6L15.6 7 17 15H3zm0 1.5h14V18H3z"/></svg>',
    priority:    '<svg viewBox="0 0 20 20" fill="currentColor"><rect x="3" y="11" width="3" height="6" rx="0.5"/><rect x="8.5" y="7" width="3" height="10" rx="0.5"/><rect x="14" y="3" width="3" height="14" rx="0.5"/></svg>',
    parent_task: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4h10M8 10h7M8 16h7"/><path d="M5 4v12"/></svg>',
    due:         '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="14" height="12" rx="1.5"/><path d="M3 9h14M7 3v4M13 3v4"/></svg>'
  }.freeze
  private_constant :TASK_PILL_ICONS

  def task_pill_icon(name)
    svg = TASK_PILL_ICONS.fetch(name) { raise ArgumentError, "unknown task pill icon: #{name.inspect}" }
    svg.html_safe
  end

  def task_card_last_activity(task)
    last_run = task.runs.order(:created_at).last
    return nil unless last_run
    "Run ##{last_run.id} #{run_status_glyph(last_run.status)}"
  end

  def audit_event_description(event)
    meta = event.metadata
    case event.action
    when "created"           then "Task created"
    when "task_advanced"     then "Advanced to #{meta['to_column_name']}"
    when "task_rejected"     then "Sent back to #{meta['to_column_name']}"
    when "task_blocked"      then "Blocked: #{meta['reason']}"
    when "task_manual_moved" then "Moved to #{meta['to_column_name']}"
    when "task_cancelled"    then "Cancelled"
    else event.action.humanize
    end
  end

  private

  def run_status_glyph(status)
    case status
    when "completed" then "✓"
    when "failed", "budget_exceeded" then "✗"
    when "cancelled" then "⊘"
    when "running" then "▶"
    else "•"
    end
  end
end
