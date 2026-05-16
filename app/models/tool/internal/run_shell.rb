require "open3"
require "timeout"

class Tool::Internal::RunShell < Tool::Internal
  # SECURITY NOTE: chdir to ${MOP_HOME} is the *only* sandboxing for shell
  # execution. A command like `cd /etc && cat passwd` escapes trivially.
  # Phase 4's supervisor v2 rewrite moves shell execution into a child
  # process where rlimits + uid drop + namespaces become tractable;
  # until then, `run_shell` is admin-only and the audit log is the safety net.
  MAX_OUTPUT_BYTES = 64 * 1024
  TIMEOUT_SECONDS  = 30

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

    cwd = Rails.application.config.x.mop_home
    output, status = Timeout.timeout(TIMEOUT_SECONDS) do
      stdout, stderr, st = Open3.capture3(command, chdir: cwd)
      [ "$ #{command}\n#{stdout}#{stderr}", st ]
    end
    if output.bytesize > MAX_OUTPUT_BYTES
      output = output.byteslice(0, MAX_OUTPUT_BYTES).to_s.scrub + "\n…[truncated]"
    end
    status.success? ? Tool::Result.ok(output) : Tool::Result.failure("exit #{status.exitstatus}: #{output}")
  rescue Timeout::Error
    Tool::Result.failure("timed out after #{TIMEOUT_SECONDS}s")
  end
end
