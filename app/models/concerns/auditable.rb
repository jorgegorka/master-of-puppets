module Auditable
  extend ActiveSupport::Concern

  included do
    has_many :audit_events, as: :auditable, dependent: :delete_all
  end

  def record_audit_event!(actor:, action:, metadata: {}, project: nil)
    resolved_project = project || try(:project) || Current.project
    audit_events.create!(
      actor: actor,
      action: action,
      metadata: metadata,
      project: resolved_project
    )
  end

  # Record a destroy event on the project instead of the model itself,
  # because `has_many :audit_events, dependent: :delete_all` would
  # immediately remove an event attached to the destroyed record.
  def record_destroy_audit_event!(actor:, metadata: {})
    resolved_project = try(:project) || Current.project
    return unless resolved_project

    AuditEvent.create!(
      auditable: resolved_project,
      actor: actor,
      action: "destroyed",
      metadata: metadata.merge(destroyed_type: self.class.name, destroyed_id: id),
      project: resolved_project
    )
  end

  def audit_destroyed
    actor = audit_actor
    return unless actor

    record_destroy_audit_event!(actor: actor, metadata: { title: try(:title) || try(:name) })
  end

  private

  def audit_actor
    Current.user || try(:creator) || try(:column)
  end
end
