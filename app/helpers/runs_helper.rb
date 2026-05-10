module RunsHelper
  def run_status_badge(run)
    css_class = "status-badge status-badge--#{run.status}"
    tag.span(run.status.humanize, class: css_class)
  end

  def run_duration(run)
    return "---" unless run.started_at && run.finished_at
    seconds = (run.finished_at - run.started_at).round(1)
    if seconds < 60
      "#{seconds}s"
    else
      minutes = (seconds / 60).floor
      remaining = (seconds % 60).round
      "#{minutes}m #{remaining}s"
    end
  end
end
