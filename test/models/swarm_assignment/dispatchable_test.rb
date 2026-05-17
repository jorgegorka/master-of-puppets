require "test_helper"

class SwarmAssignment::DispatchableTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
  end

  test "dispatch! calls TmuxBridge.spawn_worker + transitions to :dispatched + tracks event" do
    asg = SwarmAssignment.create!(swarm_mission: swarm_missions(:alpha),
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "Build the X feature")
    spawn_args = nil
    send_keys_args = nil
    with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(a) {
      spawn_args = a
      { tmux_session_name: "mop-swarm-#{a.id}", fifo: "/tmp/x" }
    }) do
      with_singleton_method(Swarm::TmuxBridge, :send_keys, ->(a, data) {
        send_keys_args = [ a, data ]
      }) do
        assert_difference -> { Event.where(action: "swarm_assignment_dispatched").count }, 1 do
          asg.dispatch!
        end
      end
    end
    assert_equal asg,                       spawn_args
    assert_equal asg,                       send_keys_args.first
    assert_match(/Build the X feature/,     send_keys_args.last)
    assert_predicate asg, :dispatched?
    assert_equal "mop-swarm-#{asg.id}", asg.tmux_session_name
    assert_not_nil asg.dispatched_at
  end

  test "dispatch_ready dispatches all unblocked pending assignments" do
    mission = swarm_missions(:alpha)
    first = SwarmAssignment.create!(swarm_mission: mission, agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "T1", state: :completed)
    ready = SwarmAssignment.create!(swarm_mission: mission, agent_profile: AgentProfile.find_by!(slug: "frontend"),
                                    task: "T2", depends_on: [ first.id ])
    not_ready = SwarmAssignment.create!(swarm_mission: mission, agent_profile: AgentProfile.find_by!(slug: "frontend"),
                                        task: "T3", depends_on: [ ready.id ])
    with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(_) { { tmux_session_name: "x", fifo: "/tmp/x" } }) do
      with_singleton_method(Swarm::TmuxBridge, :send_keys, ->(_a, _d) { nil }) do
        SwarmAssignment.dispatch_ready(mission: mission)
      end
    end
    assert_predicate ready.reload, :dispatched?
    assert_predicate not_ready.reload, :pending?
  end

  test "block!(reason) flips to :blocked, records reason, fires event, flips mission to :blocked" do
    asg = SwarmAssignment.create!(swarm_mission: swarm_missions(:alpha),
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :running)
    assert_difference -> { Event.where(action: "swarm_assignment_blocked").count }, 1 do
      asg.block!(reason: "Need DB creds")
    end
    assert_predicate asg, :blocked?
    assert_equal "Need DB creds", asg.block_reason
    assert_predicate asg.swarm_mission.reload, :blocked?
  end

  test "complete! tears down the tmux session and runs orchestrator advance" do
    asg = SwarmAssignment.create!(swarm_mission: swarm_missions(:alpha),
                                  agent_profile: AgentProfile.find_by!(slug: "backend"),
                                  task: "T", state: :running, tmux_session_name: "mop-swarm-1")
    closed = nil
    with_singleton_method(Swarm::TmuxBridge, :close_worker, ->(a) { closed = a; { ok: true } }) do
      asg.complete!
    end
    assert_equal asg, closed
    assert_predicate asg, :completed?
    assert_not_nil asg.finished_at
  end
end
