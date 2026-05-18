require "test_helper"

class SwarmMission::AdvanceableTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
  end

  teardown { Swarm::OutputBuffer.instance_variable_set(:@singleton, nil) }

  def push_output(asg, text)
    Swarm::OutputBuffer.singleton.instance_variable_get(:@buffers)[asg.id] << text
  end

  test "advance! parses a checkpoint and creates a SwarmCheckpoint row" do
    mission = swarm_missions(:alpha); mission.update!(state: :executing)
    asg = SwarmAssignment.create!(swarm_mission: mission,
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :running)
    push_output(asg, <<~OUT)
      ===HERMES CHECKPOINT===
      state_label: working
      runtime_state: { step: 1 }
      files_changed: ["a.rb"]
      commands_run: []
      result: "Made progress"
      blocker: null
      next_action: "Keep going"
      ===END CHECKPOINT===
    OUT

    assert_difference -> { asg.checkpoints.count }, 1 do
      mission.advance!
    end
    cp = asg.checkpoints.last
    assert_equal "working", cp.state_label
    assert_predicate asg.reload, :running?
  end

  test "advance! detects blocker -> assignment.block! + mission flips to :blocked" do
    mission = swarm_missions(:alpha); mission.update!(state: :executing)
    asg = SwarmAssignment.create!(swarm_mission: mission,
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :running)
    push_output(asg, <<~OUT)
      ===HERMES CHECKPOINT===
      state_label: stuck
      runtime_state: {}
      files_changed: []
      commands_run: []
      result: null
      blocker: "Need credentials"
      next_action: null
      ===END CHECKPOINT===
    OUT
    mission.advance!
    assert_predicate asg.reload, :blocked?
    assert_predicate mission.reload, :blocked?
  end

  test "advance! completes assignment + completes mission once all assignments resolve" do
    mission = swarm_missions(:alpha); mission.update!(state: :executing)
    asg = SwarmAssignment.create!(swarm_mission: mission,
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :running)
    push_output(asg, <<~OUT)
      ===HERMES CHECKPOINT===
      state_label: done
      runtime_state: {}
      files_changed: []
      commands_run: []
      result: "All wrapped up"
      blocker: null
      next_action: null
      ===END CHECKPOINT===
    OUT
    with_singleton_method(Swarm::TmuxBridge, :close_worker, ->(_a) { nil }) do
      mission.advance!
    end
    assert_predicate asg.reload, :completed?
    assert_predicate mission.reload, :complete?
  end

  test "advance! with all assignments failed emits swarm_mission_completion_failed event" do
    mission = swarm_missions(:alpha); mission.update!(state: :executing)
    asg = SwarmAssignment.create!(swarm_mission: mission,
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :failed)

    with_singleton_method(Swarm::TmuxBridge, :close_worker, ->(_a) { nil }) do
      mission.advance!
    end

    assert_predicate mission.reload, :complete?
    assert_equal "swarm_mission_completion_failed", mission.events.last.action
  end

  test "apply_stanza skips post-completion stanzas when buffer contains two checkpoints and first is done" do
    mission = swarm_missions(:alpha); mission.update!(state: :executing)
    asg = SwarmAssignment.create!(swarm_mission: mission,
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :running)
    push_output(asg, <<~OUT)
      ===HERMES CHECKPOINT===
      state_label: done
      runtime_state: {}
      files_changed: []
      commands_run: []
      result: "Finished first"
      blocker: null
      next_action: null
      ===END CHECKPOINT===
      Some trailing worker output between stanzas.
      ===HERMES CHECKPOINT===
      state_label: stale_followup
      runtime_state: {}
      files_changed: []
      commands_run: []
      result: "Should be ignored"
      blocker: null
      next_action: null
      ===END CHECKPOINT===
    OUT

    with_singleton_method(Swarm::TmuxBridge, :close_worker, ->(_a) { nil }) do
      mission.advance!
    end

    assert_equal 1, asg.checkpoints.count,
                 "expected only one checkpoint (pre-completion), got #{asg.checkpoints.count}"
    assert_equal 1, SwarmEvent.where(kind: "checkpoint", swarm_assignment: asg).count,
                 "expected only one checkpoint SwarmEvent, got #{SwarmEvent.where(kind: "checkpoint", swarm_assignment: asg).count}"
    assert_predicate asg.reload, :completed?
  end

  test ".advance_all_active processes every non-terminal mission" do
    m1 = swarm_missions(:alpha);     m1.update!(state: :executing)
    swarm_missions(:alpha_cancelled)  # already cancelled, will be filtered by .active
    called_on = []
    with_singleton_method(SwarmMission, :active, -> { [ m1 ] }) do
      with_singleton_method(m1, :advance!, -> { called_on << m1 }) do
        SwarmMission.advance_all_active
      end
    end
    assert_equal [ m1 ], called_on
  end
end
