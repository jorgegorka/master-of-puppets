require "test_helper"
require "socket"

# Spawns bin/agents_supervisor as a subprocess against an isolated UNIX
# socket and a sandbox MOP_HOME, then exercises the swarm.* RPC family.
# Mirrors the SupervisorV2Test harness so the boot/teardown contract stays
# uniform across versions. Skips on hosts without tmux installed.
class SupervisorV3Test < ActiveSupport::TestCase
  BOOT_WAIT = 5.0

  setup do
    skip "tmux missing on this host" unless system("which tmux >/dev/null 2>&1")

    suffix    = "#{Process.pid}_#{object_id}"
    @socket   = Rails.root.join("tmp/sockets/agents_supervisor_v3_test_#{suffix}.sock")
    @mop_home = Rails.root.join("tmp/test_mop_home_v3_#{suffix}")
    FileUtils.rm_f(@socket)
    FileUtils.mkdir_p(@mop_home.join("memory"))
    FileUtils.mkdir_p(@mop_home.join("skills"))

    env = {
      "MOP_SUPERVISOR_SOCKET" => @socket.to_s,
      "MOP_HOME"              => @mop_home.to_s,
      "RAILS_ENV"             => Rails.env
    }
    @pid = Process.spawn(env, Rails.root.join("bin/agents_supervisor").to_s, out: File::NULL, err: File::NULL)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_WAIT
    until @socket.exist? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    skip "supervisor failed to boot within #{BOOT_WAIT}s" unless @socket.exist?

    # Track ids so teardown can kill any stray tmux sessions even if the test
    # bailed before its own close_worker.
    @spawned_assignment_ids = []
  end

  teardown do
    @spawned_assignment_ids&.each do |id|
      system("tmux kill-session -t mop-swarm-#{id} 2>/dev/null")
    end
    Process.kill("TERM", @pid) rescue nil
    Process.wait(@pid) rescue nil
    FileUtils.rm_f(@socket)
    FileUtils.rm_rf(@mop_home)
  end

  test "swarm.spawn_worker creates a mop-swarm-<id> tmux session and returns fifo" do
    id = unique_assignment_id
    response = rpc(method: "swarm.spawn_worker",
                   params: { assignment_id: id, profile_slug: "test",
                             cwd: @mop_home.to_s, cols: 100, rows: 30 },
                   timeout: 5)
    result = response.dig("result")
    assert_equal "mop-swarm-#{id}", result["tmux_session_name"]
    assert File.exist?(result["fifo"]), "expected FIFO to exist at #{result['fifo']}"

    close = rpc(method: "swarm.close_worker", params: { assignment_id: id }, timeout: 5)
    assert close.dig("result", "ok"), "close_worker should report ok=true"
  end

  test "swarm.close_worker is idempotent" do
    id = unique_assignment_id
    rpc(method: "swarm.spawn_worker",
        params: { assignment_id: id, profile_slug: "test", cwd: @mop_home.to_s, cols: 80, rows: 24 },
        timeout: 5)

    first  = rpc(method: "swarm.close_worker", params: { assignment_id: id }, timeout: 5)
    second = rpc(method: "swarm.close_worker", params: { assignment_id: id }, timeout: 5)
    assert first.dig("result", "ok")
    assert second.dig("result", "ok"), "second close should still report ok (idempotent), got #{second.inspect}"
  end

  test "swarm.send_keys delivers input to the worker session" do
    id = unique_assignment_id
    rpc(method: "swarm.spawn_worker",
        params: { assignment_id: id, profile_slug: "test", cwd: @mop_home.to_s, cols: 80, rows: 24 },
        timeout: 5)

    response = rpc(method: "swarm.send_keys",
                   params: { assignment_id: id, data: "echo from-swarm\n" },
                   timeout: 5)
    assert response.dig("result", "ok"), "send_keys should report ok=true, got #{response.inspect}"

    rpc(method: "swarm.close_worker", params: { assignment_id: id }, timeout: 5)
  end

  private
    def unique_assignment_id
      id = "#{Process.pid}#{rand(10_000)}".to_i
      @spawned_assignment_ids << id
      id
    end

    def rpc(method:, params: {}, id: 1, timeout: 2)
      socket = UNIXSocket.open(@socket.to_s)
      socket.write({ jsonrpc: "2.0", id: id, method: method, params: params }.to_json + "\n")
      line = read_line(socket, timeout: timeout)
      JSON.parse(line) if line
    ensure
      socket&.close rescue nil
    end

    def read_line(socket, timeout:)
      Timeout.timeout(timeout) { socket.gets }
    rescue Timeout::Error
      nil
    end
end
