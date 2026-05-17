class SwarmAssignment < ApplicationRecord
  include Eventable

  belongs_to :swarm_mission, inverse_of: :assignments
  belongs_to :agent_profile
  belongs_to :chat_session, optional: true
  # Bridge: SwarmCheckpoint model lands in Task 6.7. The destroy cascade
  # through SwarmMission → SwarmAssignment forces Rails to resolve the
  # `dependent:` target class eagerly during User.destroy_all, so we
  # declare the association without a cascade for now. Task 6.7 will
  # re-add `dependent: :destroy` alongside the SwarmCheckpoint model.
  has_many   :checkpoints, class_name: "SwarmCheckpoint",
                           foreign_key: :swarm_assignment_id

  enum :state, { pending: 0, dispatched: 1, running: 2, completed: 3,
                 failed: 4, blocked: 5, cancelled: 6 }

  validates :task, presence: true

  scope :pending_state, -> { where(state: :pending) }
  scope :ready, -> {
    pending_completed_ids = where(state: :completed).pluck(:id).to_set
    pending_state.select do |a|
      Array(a.depends_on).all? { |id| pending_completed_ids.include?(id) }
    end
  }
  scope :live, -> { where(state: %i[dispatched running blocked]) }
  scope :resolved, -> { where(state: %i[completed failed cancelled]) }

  # No transition methods yet — Tasks 6.10, 6.14, 6.15 add dispatch!, advance!,
  # block!, unblock!, complete!, fail!, cancel!.
end
