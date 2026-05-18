require "test_helper"

class Swarm::DecompositionJobTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
  end

  test "perform delegates to mission.decompose!" do
    mission = swarm_missions(:alpha)
    called = false
    with_singleton_method(mission, :decompose!, -> { called = true }) do
      # Stub dispatch! so it's a no-op for this unit test
      with_singleton_method(mission, :dispatch!, -> { nil }) do
        Swarm::DecompositionJob.new.perform(mission)
      end
    end
    assert called
  end

  test "perform chains dispatch! for auto-mode mission after successful decomposition" do
    mission = swarm_missions(:alpha)
    assert_predicate mission, :auto?

    plan = {
      "decomposition_notes" => "Two tasks",
      "assignments" => [
        { "agent_slug" => "backend", "task" => "Write the API", "review_required" => false },
        { "agent_slug" => "frontend", "task" => "Build the UI", "review_required" => false }
      ]
    }

    spawn_calls = []
    send_keys_calls = []

    with_decomposition(plan) do
      with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(a) {
        spawn_calls << a.id
        { tmux_session_name: "mop-swarm-#{a.id}", fifo: "/tmp/x" }
      }) do
        with_singleton_method(Swarm::TmuxBridge, :send_keys, ->(a, _data) {
          send_keys_calls << a.id
        }) do
          Swarm::DecompositionJob.new.perform(mission)
        end
      end
    end

    mission.reload
    assert_predicate mission, :executing?
    assert_equal 2, mission.assignments.count
    assert_equal 2, spawn_calls.size, "expected spawn_worker called for each assignment"
  end

  test "perform does NOT call dispatch! for manual-mode mission" do
    manual = SwarmMission.create!(
      user: users(:one), created_by: users(:one),
      title: "Manual mission", goal: "G", mode: :manual
    )

    plan = {
      "decomposition_notes" => "One task",
      "assignments" => [
        { "agent_slug" => "backend", "task" => "Do the thing", "review_required" => false }
      ]
    }

    dispatched = false
    with_decomposition(plan) do
      with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(_a) {
        dispatched = true
        { tmux_session_name: "mop-swarm-1", fifo: "/tmp/x" }
      }) do
        with_singleton_method(Swarm::TmuxBridge, :send_keys, ->(_a, _d) { nil }) do
          Swarm::DecompositionJob.new.perform(manual)
        end
      end
    end

    manual.reload
    assert_predicate manual, :dispatching?, "manual mission should remain :dispatching (not auto-dispatched)"
    assert_not dispatched, "spawn_worker should not be called for manual-mode missions"
  end
end
