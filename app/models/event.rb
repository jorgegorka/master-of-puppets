class Event < ApplicationRecord
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :eventable, polymorphic: true

  INCIDENT_PATTERNS = %w[
    %_failed
    %_errored
    %_error_%
    error_%
  ].freeze

  scope :incidents, lambda {
    pattern_predicate = INCIDENT_PATTERNS.map { "action LIKE ?" }.join(" OR ")
    where(pattern_predicate, *INCIDENT_PATTERNS)
      .where.not(action: %w[skill_reloaded memory_file_reloaded])
      .order(occurred_at: :desc)
  }

  after_create_commit :notify_eventable

  # Dashboard scope: incidents the given user has visibility on. Either:
  #  - they authored the event (creator: user), or
  #  - the event's eventable is one of their owned resources (chat_session,
  #    scheduled_job, mcp_server). Skills are global (no user_id) so they
  #    are deliberately omitted from the per-user scope.
  #
  # Uses `or` over four narrower scopes on the same base `incidents` query
  # so Active Record produces a single flat SQL statement; the per-type
  # subqueries via `select(:id)` keep the IN clauses server-side.
  def self.incidents_for(user)
    incidents.where(creator: user)
      .or(incidents.where(eventable_type: "ChatSession",
                          eventable_id: user.chat_sessions.select(:id)))
      .or(incidents.where(eventable_type: "ScheduledJob",
                          eventable_id: user.scheduled_jobs.select(:id)))
      .or(incidents.where(eventable_type: "McpServer",
                          eventable_id: user.mcp_servers.select(:id)))
  end

  private
    def notify_eventable
      eventable.try(:event_was_created, self)
    end
end
