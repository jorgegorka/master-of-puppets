module SwarmAssignment::Dispatchable
  extend ActiveSupport::Concern

  KICKOFF_TEMPLATE = <<~PROMPT
    You are a swarm worker. Your task:

    %{task}

    When you reach a milestone (or are blocked), emit a YAML checkpoint
    between these sentinels (no other text inside):

    ===HERMES CHECKPOINT===
    state_label: <one-token>
    runtime_state: { step: 1 }
    files_changed: []
    commands_run: []
    result: <short prose>
    blocker: null              # set to a string if you cannot proceed
    next_action: <short prose>
    ===END CHECKPOINT===

    Begin.
  PROMPT

  class_methods do
    def dispatch_ready(mission:)
      mission.assignments.ready.each(&:dispatch!)
    end
  end

  def resolved?
    completed? || failed? || cancelled?
  end

  def dispatch!
    return unless pending?

    transaction do
      result = Swarm::TmuxBridge.spawn_worker(self)
      update!(state: :dispatched,
              tmux_session_name: result[:tmux_session_name] || result["tmux_session_name"],
              dispatched_at: Time.current)
      track_event :dispatched, agent_slug: agent_profile.slug
    end
    Swarm::TmuxBridge.send_keys(self, kickoff_prompt + "\n")
    SwarmEvent.log!(mission: swarm_mission, assignment: self,
                    kind: "dispatched", message: "Worker spawned",
                    data: { tmux: tmux_session_name })
  end

  def mark_running!
    return unless dispatched?

    update!(state: :running)
    track_event :started
  end

  def complete!
    return if resolved?

    begin
      Swarm::TmuxBridge.close_worker(self)
    rescue
      nil
    end
    update!(state: :completed, finished_at: Time.current)
    track_event :completed
  end

  def fail!(reason: nil)
    return if resolved?

    begin
      Swarm::TmuxBridge.close_worker(self)
    rescue
      nil
    end
    update!(state: :failed, finished_at: Time.current, block_reason: reason)
    track_event :failed, reason: reason
  end

  def cancel!
    return if resolved?

    begin
      Swarm::TmuxBridge.close_worker(self)
    rescue
      nil
    end
    update!(state: :cancelled, finished_at: Time.current)
    track_event :cancelled
  end

  def block!(reason:)
    return unless %w[dispatched running].include?(state)

    transaction do
      update!(state: :blocked, block_reason: reason)
      swarm_mission.update!(state: :blocked) unless swarm_mission.blocked?
      track_event :blocked, reason: reason
    end
    SwarmEvent.log!(mission: swarm_mission, assignment: self,
                    kind: "blocked", message: reason, data: {})
  end

  def unblock!(operator_input:)
    return unless blocked?

    Swarm::TmuxBridge.send_keys(self, operator_input + "\n")
    update!(state: :running, block_reason: nil)
    track_event :unblocked
  end

  private
    def kickoff_prompt
      format(KICKOFF_TEMPLATE, task: task)
    end
end
