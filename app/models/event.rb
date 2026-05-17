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

  private
    def notify_eventable
      eventable.try(:event_was_created, self)
    end
end
