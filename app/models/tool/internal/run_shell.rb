require "open3"
require "timeout"

class Tool::Internal::RunShell < Tool::Internal
  MAX_OUTPUT_BYTES   = 64 * 1024
  TIMEOUT_SECONDS    = 30
  KILL_GRACE_SECONDS = 2

  # Mirror the supervisor's scrub list so the in-process fallback (tests,
  # MOP_RUN_SHELL_FORCE_IN_PROCESS=1) gets the same protection.
  SCRUBBED_ENV = %w[
    DATABASE_URL
    RAILS_MASTER_KEY
    SECRET_KEY_BASE
    ANTHROPIC_API_KEY
    OPENAI_API_KEY
  ].freeze

  def self.tool_name;   "run_shell"; end
  def self.description; "Run a shell command in the workspace (admin only, sandboxed via cwd, 30s timeout, rlimits via supervisor)."; end
  def self.input_schema
    {
      type: "object",
      properties: {
        command: { type: "string", description: "Shell command to execute." }
      },
      required: [ "command" ]
    }
  end

  def self.invoke(input:, user:)
    return Tool::Result.failure("run_shell is admin-only") unless user&.admin?

    command = input.fetch("command").to_s
    return Tool::Result.failure("empty command") if command.strip.empty?

    if ENV["MOP_RUN_SHELL_FORCE_IN_PROCESS"] == "1"
      invoke_in_process(command)
    else
      invoke_via_supervisor(command)
    end
  end

  # Default Phase 4 path: dispatch through the supervisor's shell.run RPC,
  # so the child gets rlimits + env scrub + pgroup + (Linux + root) uid drop.
  # If the supervisor isn't reachable, fall back to the in-process path so
  # dev environments without a running supervisor can still test the tool.
  def self.invoke_via_supervisor(command)
    # Run mop_home through WorkspacePath so a symlinked or relocated config
    # value is realpath-resolved before the supervisor uses it as cwd —
    # matches the resolution every other workspace-touching path takes.
    cwd = WorkspacePath.resolve(root: ".", raw: ".").absolute.to_s
    result = AgentsSupervisor::Client.call("shell.run", { command: command, cwd: cwd, timeout: TIMEOUT_SECONDS }, timeout: TIMEOUT_SECONDS + 5)

    if result["timed_out"]
      return Tool::Result.failure("timed out after #{TIMEOUT_SECONDS}s")
    end

    body = "$ #{command}\n#{result['stdout']}#{result['stderr']}".byteslice(0, MAX_OUTPUT_BYTES * 2).to_s
    exit_code = result["exit_code"].to_i
    if exit_code.zero?
      Tool::Result.ok(body)
    else
      Tool::Result.failure("exit #{exit_code}: #{body}")
    end
  rescue Errno::ENOENT, Errno::ECONNREFUSED, AgentsSupervisor::SupervisorError => e
    Rails.logger.warn("[run_shell] supervisor RPC failed (#{e.class}: #{e.message}); falling back to in-process")
    invoke_in_process(command)
  end

  # In-process fallback (Phase 3 codepath, kept for tests + supervisor-less
  # dev). Scrubs sensitive env vars; runs in its own process group so a
  # timeout kills the whole tree.
  def self.invoke_in_process(command)
    output, status = run_with_timeout(command)
    if output.bytesize > MAX_OUTPUT_BYTES
      output = output.byteslice(0, MAX_OUTPUT_BYTES).to_s.scrub + "\n…[truncated]"
    end
    status.success? ? Tool::Result.ok(output) : Tool::Result.failure("exit #{status.exitstatus}: #{output}")
  rescue Timeout::Error
    Tool::Result.failure("timed out after #{TIMEOUT_SECONDS}s")
  end

  def self.scrubbed_env
    SCRUBBED_ENV.each_with_object({}) { |k, h| h[k] = nil }
  end

  def self.run_with_timeout(command)
    cwd = Rails.application.config.x.mop_home
    pid = nil
    stdin, stdout, stderr, wait_thr = Open3.popen3(scrubbed_env, command, chdir: cwd, pgroup: true)
    stdin.close
    pid = wait_thr.pid
    begin
      out, err, status = Timeout.timeout(TIMEOUT_SECONDS) do
        [ stdout.read, stderr.read, wait_thr.value ]
      end
      [ "$ #{command}\n#{out}#{err}", status ]
    rescue Timeout::Error
      terminate_process_group!(pid)
      raise
    ensure
      stdout.close unless stdout.closed?
      stderr.close unless stderr.closed?
    end
  end

  def self.terminate_process_group!(pid)
    return if pid.nil?
    Process.kill("-TERM", pid)
    deadline = Time.now + KILL_GRACE_SECONDS
    while Time.now < deadline
      Process.waitpid(pid, Process::WNOHANG) and return
      sleep 0.05
    end
    Process.kill("-KILL", pid)
    Process.waitpid(pid, Process::WNOHANG)
  rescue Errno::ESRCH, Errno::ECHILD
    # Already gone — nothing to do.
  end
end
