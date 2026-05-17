class Event < ApplicationRecord
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :eventable, polymorphic: true

  INFO_RETENTION_DAYS    = 90
  FAILURE_RETENTION_DAYS = 365

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

  # Recurring sweeper: drops :info events older than 90 days and failure
  # events (action LIKE '%_failed') older than 365 days. Keeps the audit
  # trail bounded without losing recent context or long-tail failures.
  def self.prune!
    info_cutoff    = INFO_RETENTION_DAYS.days.ago
    failure_cutoff = FAILURE_RETENTION_DAYS.days.ago
    transaction do
      where("occurred_at < ? AND action NOT LIKE ?", info_cutoff, "%_failed").delete_all
      where("occurred_at < ? AND action LIKE ?",     failure_cutoff, "%_failed").delete_all
    end
  end

  private
    def notify_eventable
      eventable.try(:event_was_created, self)
    end
end
