require "test_helper"
require "support/method_stub"

class Swarm::TmuxBridgeTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    @assignment = SwarmAssignment.create!(
      swarm_mission: swarm_missions(:alpha),
      agent_profile: agent_profiles(:backend),
      task: "Do the thing"
    )
  end

  test "spawn_worker calls swarm.spawn_worker with hardened cwd + profile metadata" do
    captured = nil
    assignment = @assignment
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) {
      captured = [ method, params ]
      { "tmux_session_name" => "mop-swarm-#{assignment.id}", "fifo" => "/tmp/x.fifo" }
    }) do
      Swarm::TmuxBridge.spawn_worker(@assignment)
    end

    assert_equal "swarm.spawn_worker", captured[0]
    params = captured[1]
    assert_equal @assignment.id, params[:assignment_id]
    assert_equal "backend",      params[:profile_slug]
    assert_equal 120,            params[:cols]
    assert_equal 40,             params[:rows]
    # cwd should resolve under MOP_HOME, not be the raw "agents/backend"
    assert params[:cwd].start_with?(Rails.application.config.x.mop_home.to_s),
      "expected cwd to be under MOP_HOME, got #{params[:cwd]}"
  end

  test "spawn_worker raises WorkspacePath::EscapeAttempt for traversal probes" do
    @assignment.agent_profile.update!(cwd: "../../etc")
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) { fail "should not reach supervisor" }) do
      assert_raises WorkspacePath::EscapeAttempt do
        Swarm::TmuxBridge.spawn_worker(@assignment)
      end
    end
  end

  test "send_keys forwards to swarm.send_keys" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) {
      captured = [ method, params ]
      { "ok" => true }
    }) do
      Swarm::TmuxBridge.send_keys(@assignment, "yes\n")
    end
    assert_equal [ "swarm.send_keys", { assignment_id: @assignment.id, data: "yes\n" } ], captured
  end

  test "close_worker forwards to swarm.close_worker" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) {
      captured = [ method, params ]
      { "ok" => true }
    }) do
      Swarm::TmuxBridge.close_worker(@assignment)
    end
    assert_equal [ "swarm.close_worker", { assignment_id: @assignment.id } ], captured
  end

  test "fifo_path returns tmp/sockets/swarm-<id>.fifo under Rails.root" do
    path = Swarm::TmuxBridge.fifo_path(@assignment)
    assert_equal Rails.root.join("tmp/sockets/swarm-#{@assignment.id}.fifo").to_s, path.to_s
  end
end
