class Dashboard::Show
  RECENT_RUNS_LIMIT = 10
  INCIDENTS_LIMIT   = 20

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def rollup
    @rollup ||= Dashboard::Rollup.new(scope: messages_scope)
  end

  def incidents
    @incidents ||= Event.incidents_for(user).limit(INCIDENTS_LIMIT)
  end

  def recent_runs
    @recent_runs ||= JobRun.eager_load(:scheduled_job)
                           .where(scheduled_jobs: { user_id: user.id })
                           .recent
                           .limit(RECENT_RUNS_LIMIT)
  end

  def mcp_servers
    @mcp_servers ||= user.mcp_servers.order(:name)
  end

  private
    def messages_scope
      Message.joins(:chat_session).where(chat_sessions: { user_id: user.id })
    end
end
