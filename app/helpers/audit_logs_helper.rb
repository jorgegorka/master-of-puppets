module AuditLogsHelper
  def audit_action_badge(action)
    css_class = case action
    when *AuditEvent::GOVERNANCE_ACTIONS
                  "audit-badge--governance"
    when "created", "task_advanced"
                  "audit-badge--info"
    when "task_manual_moved", "updated"
                  "audit-badge--change"
    when "destroyed", "task_blocked", "task_rejected", "task_cancelled"
                  "audit-badge--danger"
    else
                  "audit-badge--default"
    end
    tag.span(action.humanize, class: "audit-badge #{css_class}")
  end

  def audit_actor_display(event)
    polymorphic_actor_label(event)
  end

  def audit_auditable_display(event)
    case event.auditable_type
    when "Task"
      link_to_if(event.auditable, event.auditable&.title || "Deleted task", event.auditable)
    when "Column"
      link_to_if(event.auditable, event.auditable&.name || "Deleted column", event.auditable ? column_path(event.auditable) : "#")
    when "Run"
      link_to_if(event.auditable, "Run ##{event.auditable_id}", event.auditable ? run_path(event.auditable) : "#")
    when "Project"
      label = event.auditable&.name || "Project"
      if event.action == "destroyed" && event.metadata["destroyed_type"].present?
        "#{event.metadata['destroyed_type']}: #{event.metadata['title'] || event.metadata['destroyed_id']}"
      else
        label
      end
    else
      "#{event.auditable_type} ##{event.auditable_id}"
    end
  end

  def audit_metadata_display(metadata)
    return "" if metadata.blank?
    metadata.map { |k, v| "#{k.humanize}: #{v}" }.join(", ")
  end
end
