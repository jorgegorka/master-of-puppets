module SwarmMission::Advanceable
  extend ActiveSupport::Concern

  class_methods do
    def advance_all_active
      SwarmMission.active.each(&:advance!)
    end
  end

  def advance!
    return if planning? || resolved_terminally?

    assignments.live.find_each do |asg|
      process_assignment(asg)
    end

    transition_after_assignments
  end

  private
    def resolved_terminally?
      complete? || cancelled?
    end

    def process_assignment(asg)
      Swarm::OutputBuffer.singleton.drain(asg)
      text = Swarm::OutputBuffer.singleton.consume(asg.id)
      return if text.empty?

      asg.mark_running! if asg.dispatched?
      SwarmCheckpoint.parse(text).each { |stanza| apply_stanza(asg, stanza) }
    end

    def apply_stanza(asg, stanza)
      return if asg.resolved?

      asg.checkpoints.create!(
        state_label:   stanza[:state_label],
        runtime_state: stanza[:runtime_state],
        files_changed: stanza[:files_changed],
        commands_run:  stanza[:commands_run],
        result:        stanza[:result],
        blocker:       stanza[:blocker],
        next_action:   stanza[:next_action],
        raw:           stanza[:raw]
      )
      SwarmEvent.log!(mission: self, assignment: asg, kind: "checkpoint",
                      message: stanza[:state_label], data: stanza.except(:raw))

      if stanza[:blocker].present?
        asg.block!(reason: stanza[:blocker])
      elsif stanza[:state_label] == "done" || (stanza[:result].present? && stanza[:next_action].blank?)
        asg.complete!
      end
    end

    def transition_after_assignments
      if assignments.where(state: %i[pending dispatched running blocked]).empty?
        if assignments.where(state: :failed).any?
          update!(state: :complete) # All-resolved-with-some-failures still terminal; UI surfaces failures
          track_event :completion_failed, count: assignments.where(state: :failed).count
        else
          update!(state: :complete)
          track_event :completed
        end
        SwarmEvent.log!(mission: self, kind: "completed", message: "All assignments resolved", data: {})
      elsif dispatching? && assignments.where(state: :dispatched).none?
        update!(state: :executing) if assignments.where(state: :running).any?
      elsif !blocked? && assignments.where(state: :blocked).empty? && executing?
        # Trigger ready dispatch if mode is :auto
        SwarmAssignment.dispatch_ready(mission: self) if auto?
      end
    end
end
