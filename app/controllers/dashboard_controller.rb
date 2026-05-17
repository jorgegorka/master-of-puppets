class DashboardController < ApplicationController
  def show
    scope        = Message.joins(:chat_session).where(chat_sessions: { user_id: Current.user.id })
    @rollup      = Dashboard::Rollup.new(scope: scope)
    @incidents   = Event.incidents_for(Current.user).limit(20)
    @recent_runs = JobRun.eager_load(:scheduled_job)
                         .where(scheduled_jobs: { user_id: Current.user.id })
                         .recent
                         .limit(10)
    @mcp_servers = Current.user.mcp_servers.order(:name)
  end
end
