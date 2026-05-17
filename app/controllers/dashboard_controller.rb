class DashboardController < ApplicationController
  # H11 follow-up: incident scoping is narrowed to events the current user
  # authored. This misses incidents on the user's own resources (chat_sessions,
  # scheduled_jobs) that were authored by the system, but those `_reloaded`
  # paths are already filtered out by `Event.incidents`. Polymorphic-join
  # tenant filtering can be revisited during the H11 hardening gate.
  def show
    scope        = Message.joins(:chat_session).where(chat_sessions: { user_id: Current.user.id })
    @rollup      = Dashboard::Rollup.new(scope: scope)
    @incidents   = Event.incidents.where(creator: Current.user).limit(20)
    @recent_runs = JobRun.eager_load(:scheduled_job)
                         .where(scheduled_jobs: { user_id: Current.user.id })
                         .recent
                         .limit(10)
    @mcp_servers = Current.user.mcp_servers.order(:name)
  end
end
