# SwarmEvent is high-frequency telemetry — distinct from the polymorphic
# audit `Event` table populated by Eventable. Different table, different
# retention (sweeper lands in Phase 6 hardening). Do NOT include Eventable.
class SwarmEvent < ApplicationRecord
  belongs_to :swarm_mission
  belongs_to :swarm_assignment, optional: true

  scope :recent,         -> { order(occurred_at: :desc) }
  scope :since,          ->(t) { where("occurred_at >= ?", t).recent }
  scope :for_assignment, ->(a) { where(swarm_assignment_id: a.id) }
  scope :of_kind,        ->(*k) { where(kind: k) }

  # Append-only helper: do NOT use `Event` — this is telemetry, not audit.
  def self.log!(mission:, assignment: nil, kind:, message: nil, data: {}, occurred_at: Time.current)
    create!(swarm_mission: mission, swarm_assignment: assignment,
            kind: kind.to_s, message: message, data: data, occurred_at: occurred_at)
  end
end
