module NotificationsHelper
  def notification_icon(notification)
    case notification.action
    when "budget_alert" then "warning"
    when "budget_exhausted" then "error"
    when "run_failed" then "error"
    else "info"
    end
  end

  def notification_message(notification)
    meta = notification.metadata
    case notification.action
    when "budget_alert"
      "#{meta['column_name']} has used #{meta['percentage']}% of its monthly budget (#{format_cents_as_dollars(meta['spent_cents'])} of #{format_cents_as_dollars(meta['budget_cents'])})"
    when "budget_exhausted"
      "#{meta['column_name']} budget exhausted (#{format_cents_as_dollars(meta['spent_cents'])} spent)"
    when "run_failed"
      "Run failed: #{meta['error_message']}"
    else
      notification.action.humanize
    end
  end

  def notification_link(notification)
    case notification.notifiable_type
    when "Column" then column_path(notification.notifiable_id)
    when "Run"    then run_path(notification.notifiable_id)
    when "Task"   then task_path(notification.notifiable_id)
    else "#"
    end
  end
end
