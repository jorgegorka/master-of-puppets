module McpServersHelper
  # Maps status enum → semantic badge variant. Kept centralized so the
  # :disabled case (added with the Enableable concern) gets a styled badge
  # everywhere a server status is rendered.
  STATUS_BADGE_VARIANTS = {
    "reachable" => "ok",
    "error" => "danger",
    "disabled" => "muted",
    "unknown" => "warn"
  }.freeze

  def mcp_server_status_badge(server)
    variant = STATUS_BADGE_VARIANTS.fetch(server.status, "warn")
    content_tag(:span, server.status, class: "badge badge--#{variant}")
  end
end
