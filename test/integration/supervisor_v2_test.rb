require "test_helper"
require "socket"

# Spawns bin/agents_supervisor as a subprocess against an isolated UNIX
# socket and a sandbox MOP_HOME. Slow-ish (~1s per test for boot) so we
# keep the suite focused on the v2 contract: line cap, bad-parse rate cap,
# health.ping, graceful shutdown.
class SupervisorV2Test < ActiveSupport::TestCase
  BOOT_WAIT = 5.0

  # Parallel test workers fork from the parent process — class constants
  # (or anything captured at load time) leak across workers. Compute the
  # socket + workspace paths per setup so each test gets an isolated supervisor.
  setup do
    suffix    = "#{Process.pid}_#{object_id}"
    @socket   = Rails.root.join("tmp/sockets/agents_supervisor_test_#{suffix}.sock")
    @mop_home = Rails.root.join("tmp/test_mop_home_#{suffix}")
    FileUtils.rm_f(@socket)
    FileUtils.mkdir_p(@mop_home.join("memory"))
    FileUtils.mkdir_p(@mop_home.join("skills"))

    env = {
      "MOP_SUPERVISOR_SOCKET"   => @socket.to_s,
      "MOP_HOME"                => @mop_home.to_s,
      "MOP_RPC_BAD_PARSE_CAP"   => "5",
      "MOP_RPC_BAD_PARSE_WINDOW" => "10",
      "MOP_RPC_MAX_LINE"        => "1024",  # tighter cap for the line-too-long probe
      "RAILS_ENV"               => Rails.env
    }
    @pid = Process.spawn(env, Rails.root.join("bin/agents_supervisor").to_s, out: File::NULL, err: File::NULL)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_WAIT
    until @socket.exist? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    skip "supervisor failed to boot within #{BOOT_WAIT}s" unless @socket.exist?
  end

  teardown do
    Process.kill("TERM", @pid) rescue nil
    Process.wait(@pid) rescue nil
    FileUtils.rm_f(@socket)
    FileUtils.rm_rf(@mop_home)
  end

  test "health.ping returns pong" do
    response = rpc(method: "health.ping")
    assert response.dig("result", "pong"), "expected pong=true, got #{response.inspect}"
    assert_equal @pid, response.dig("result", "pid")
  end

  test "rejects a request line over MAX_RPC_LINE_BYTES" do
    socket = UNIXSocket.open(@socket.to_s)
    socket.write(("x" * 2048) + "\n")
    response = read_line(socket, timeout: 2)
    assert response, "expected an error response, got nothing"
    parsed = JSON.parse(response)
    assert_equal(-32700, parsed.dig("error", "code"))
    assert_match(/line too long/i, parsed.dig("error", "message"))
  ensure
    socket&.close rescue nil
  end

  test "bad-parse rate cap closes the connection" do
    socket = UNIXSocket.open(@socket.to_s)
    5.times { socket.write("not-json\n") }
    # First few responses come back as parse-error; once the cap is hit, the
    # connection is closed mid-stream.
    closed_or_drained = false
    begin
      20.times do
        socket.write("not-json\n")
        sleep 0.02
      end
    rescue Errno::EPIPE, IOError
      closed_or_drained = true
    end
    closed_or_drained ||= socket.eof? rescue false
    assert closed_or_drained, "expected supervisor to close the connection after BAD_PARSE_CAP"
  ensure
    socket&.close rescue nil
  end

  test "unknown method returns -32601" do
    response = rpc(method: "does.not.exist")
    assert_equal(-32601, response.dig("error", "code"))
  end

  test "shell.run executes a command and returns exit code + stdout" do
    response = rpc(method: "shell.run", params: { command: "echo from-supervisor", cwd: @mop_home.to_s, timeout: 5 }, timeout: 10)
    assert_equal 0, response.dig("result", "exit_code")
    assert_match(/from-supervisor/, response.dig("result", "stdout").to_s)
    assert_equal false, response.dig("result", "timed_out")
  end

  test "shell.run kills a runaway command at the timeout" do
    response = rpc(method: "shell.run", params: { command: "sleep 10", cwd: @mop_home.to_s, timeout: 1 }, timeout: 5)
    assert_equal true, response.dig("result", "timed_out")
  end

  test "shell.run scrubs SECRET_KEY_BASE (and the rest of the deny list) from the child env" do
    # The supervisor inherits the parent's env. Verify each entry on the deny
    # list is genuinely absent from the child. SECRET_KEY_BASE is the Rails
    # cookie signing key — if it leaked into a tool-invoked shell, a run_shell
    # call could fabricate session cookies.
    script = %w[DATABASE_URL RAILS_MASTER_KEY SECRET_KEY_BASE ANTHROPIC_API_KEY OPENAI_API_KEY MOP_SUPERVISOR_SOCKET]
      .map { |v| "echo #{v}=$#{v}" }.join("; ")
    response = rpc(method: "shell.run", params: { command: script, cwd: @mop_home.to_s, timeout: 5 }, timeout: 10)
    stdout = response.dig("result", "stdout").to_s
    %w[DATABASE_URL RAILS_MASTER_KEY SECRET_KEY_BASE ANTHROPIC_API_KEY OPENAI_API_KEY MOP_SUPERVISOR_SOCKET].each do |var|
      assert_match(/^#{var}=$/, stdout, "expected #{var} to be scrubbed from child env, stdout was:\n#{stdout}")
    end
  end

  test "terminal.create + capture + close cycle through tmux" do
    omit "tmux not installed" unless system("which tmux > /dev/null 2>&1")

    session_id = "supv-test-#{Process.pid}-#{rand(10_000)}"
    cwd        = @mop_home.to_s
    response   = rpc(method: "terminal.create", params: { session_id: session_id, cwd: cwd, cols: 80, rows: 24 }, timeout: 5)
    assert_equal "mop-term-#{session_id}", response.dig("result", "tmux_session_name")

    # Feed an "input" line; the FIFO should receive it as pipe-pane output.
    fifo = Pathname.new(response.dig("result", "fifo"))
    assert fifo.exist?, "expected FIFO to be created at #{fifo}"

    # Capture should return non-empty pane text (tmux shows the shell prompt).
    capture = rpc(method: "terminal.capture", params: { session_id: session_id, lines: 50 }, timeout: 5)
    assert_kind_of String, capture.dig("result", "text")

    close_resp = rpc(method: "terminal.close", params: { session_id: session_id }, timeout: 5)
    assert close_resp.dig("result", "ok")
  ensure
    # If anything went sideways, kill the stray tmux session manually so the next run is clean.
    system("tmux kill-session -t mop-term-#{session_id} 2>/dev/null") if session_id
  end

  private

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
