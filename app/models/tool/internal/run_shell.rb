require "open3"
require "timeout"

class Tool::Internal::RunShell < Tool::Internal
  # SECURITY NOTE: chdir to ${MOP_HOME} is the *only* sandboxing for shell
  # execution. A command like `cd /etc && cat passwd` escapes trivially.
  # Phase 4's supervisor v2 rewrite moves shell execution into a child
  # process where rlimits + uid drop + namespaces become tractable;
  # until then, `run_shell` is admin-only and the audit log is the safety net.
  # Today's mitigations (also see config/initializers/tool_internal_registry.rb):
  #   - registration is gated on MOP_ENABLE_RUN_SHELL (default off in prod)
  #   - secrets are scrubbed from the child environment (SCRUBBED_ENV)
  #   - the child runs in its own process group so a timeout kills the whole tree
  MAX_OUTPUT_BYTES = 64 * 1024
  TIMEOUT_SECONDS  = 30
  KILL_GRACE_SECONDS = 2
  SCRUBBED_ENV = %w[
    DATABASE_URL
    RAILS_MASTER_KEY
    ANTHROPIC_API_KEY
    OPENAI_API_KEY
  ].freeze

  def self.tool_name;   "run_shell"; end
  def self.description; "Run a shell command in the workspace (admin only, sandboxed via cwd, 30s timeout)."; end
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

  # Signal the whole process group so `/bin/sh -c "<long-running>"` and any
  # children die with the timeout. SIGTERM first; if the leader is still up
  # after the grace window, SIGKILL.
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
