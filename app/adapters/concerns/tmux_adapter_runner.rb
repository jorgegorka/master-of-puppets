require "open3"
require "shellwords"
require "tempfile"

# Shared tmux-spawning machinery for local CLI adapters (ClaudeLocalAdapter,
# OpencodeAdapter, and any future tmux-based adapter).
#
# Adapters extend this module to gain the full spawn/poll/capture/cleanup flow,
# plus a default `execute` with budget check + retry. They implement three hooks:
#
#   - `build_agent_command(column:, run:, prompt:, temp_files:)` -> String
#   - `env_flags(column)` -> String
#   - `parse_result(accumulated_lines)` -> Hash
module TmuxAdapterRunner
  class BudgetExhausted < StandardError; end
  class ExecutionError < StandardError; end

  POLL_INTERVAL = 0.5
  MAX_POLL_WAIT = 300
  STALL_TIMEOUT = 60
  STALL_RETRIES = 1

  PANE_WIDTH  = 500
  PANE_HEIGHT = 50

  def self.extended(base)
    base.const_set(:BudgetExhausted, BudgetExhausted) unless base.const_defined?(:BudgetExhausted, false)
    base.const_set(:ExecutionError, ExecutionError) unless base.const_defined?(:ExecutionError, false)
    base.const_set(:POLL_INTERVAL, POLL_INTERVAL) unless base.const_defined?(:POLL_INTERVAL, false)
    base.const_set(:MAX_POLL_WAIT, MAX_POLL_WAIT) unless base.const_defined?(:MAX_POLL_WAIT, false)
    base.const_set(:STALL_TIMEOUT, STALL_TIMEOUT) unless base.const_defined?(:STALL_TIMEOUT, false)
    base.const_set(:STALL_RETRIES, STALL_RETRIES) unless base.const_defined?(:STALL_RETRIES, false)
  end

  def execute(run:, prompt:, session_id: nil)
    column = run.column
    if column.budget_exhausted?
      raise BudgetExhausted, "Column budget exhausted: spent #{column.monthly_spend_cents} of #{column.budget_cents} cents budget"
    end

    retries_remaining = STALL_RETRIES
    begin
      execute_once(run: run, prompt: prompt, session_id: session_id)
    rescue ExecutionError => e
      if retries_remaining > 0 && retryable_error?(e)
        retries_remaining -= 1
        retry
      end
      raise
    end
  end

  def execute_once(run:, prompt:, session_id:)
    column      = run.column
    session_name = "#{self::SESSION_PREFIX}_#{run.id}"
    working_dir  = resolve_working_directory(column.adapter_config["working_directory"])
    temp_files   = []

    agent_cmd = build_agent_command(column: column, run: run, prompt: prompt, session_id: session_id, temp_files: temp_files)

    cmd_file = Tempfile.new([ "director_cmd", ".sh" ])
    cmd_file.write("#!/bin/sh\n#{agent_cmd}\n")
    cmd_file.flush
    cmd_file.chmod(0o755)
    temp_files << cmd_file

    spawn_cmd  = "tmux new-session -d -s #{session_name.shellescape}"
    spawn_cmd += " -x #{PANE_WIDTH} -y #{PANE_HEIGHT}"
    spawn_cmd += " -c #{working_dir.shellescape}" if working_dir.present?
    flags = env_flags(column)
    spawn_cmd += " #{flags}" if flags.present?
    spawn_cmd += " #{cmd_file.path.shellescape}"
    spawn_cmd += " \\; set-option remain-on-exit on"

    kill_session(session_name)
    spawn_session(spawn_cmd)

    accumulated_lines = poll_session(session_name, run)
    parse_result(accumulated_lines)
  ensure
    cleanup_session(session_name) if defined?(session_name) && session_name
    temp_files&.each { |f| f.close! rescue nil }
  end

  def retryable_error?(error)
    error.message.match?(/stalled|exited without producing a result/i)
  end

  def forward_env_flags(vars)
    vars.filter_map do |var|
      value = ENV[var]
      "-e #{var}=#{value.shellescape}" if value.present?
    end
  end

  def poll_sleep(seconds)
    sleep(seconds)
  end

  def spawn_session(cmd)
    stdout, stderr, status = Open3.capture3(cmd)
    unless status.success?
      raise ExecutionError, "tmux spawn failed: #{stderr.strip.presence || "unknown error (exit #{status.exitstatus})"}"
    end
    stdout
  end

  def session_exists?(name)
    system("tmux has-session -t #{name.shellescape} 2>/dev/null")
  end

  def pane_alive?(name)
    return false unless session_exists?(name)
    out, status = Open3.capture2("tmux", "display-message", "-t", name, "-p", '#{pane_dead}')
    return false unless status.success?
    out.strip == "0"
  end

  def capture_pane(name)
    `tmux capture-pane -t #{name.shellescape} -p -J -S - 2>/dev/null`
  end

  def kill_session(name)
    system("tmux kill-session -t #{name.shellescape} 2>/dev/null")
  end

  def cleanup_session(name)
    kill_session(name)
  end

  def poll_session(session_name, run)
    last_line_count = 0
    accumulated_lines = []
    poll_count = 0
    max_polls = (MAX_POLL_WAIT / POLL_INTERVAL).to_i
    last_new_output_at = Time.current

    loop do
      output = capture_pane(session_name)
      lines = output.split("\n")

      if lines.size > last_line_count
        last_new_output_at = Time.current
        new_lines = lines[last_line_count..]
        new_lines.each do |line|
          run.broadcast_line!(line + "\n")
          accumulated_lines << line
        end
        last_line_count = lines.size
      end

      break unless pane_alive?(session_name)

      stall_elapsed = Time.current - last_new_output_at
      if stall_elapsed >= STALL_TIMEOUT
        kill_session(session_name)
        raise ExecutionError, "Agent stalled: no output for #{STALL_TIMEOUT} seconds"
      end

      poll_sleep(POLL_INTERVAL)

      poll_count += 1
      if poll_count >= max_polls
        kill_session(session_name)
        raise ExecutionError, "Execution timed out after #{MAX_POLL_WAIT} seconds"
      end
    end

    accumulated_lines
  end

  def resolve_working_directory(path)
    return nil if path.blank?

    resolved = File.realpath(path)
    unless File.directory?(resolved)
      raise ExecutionError, "Working directory is not a directory: #{path} (resolved to #{resolved})"
    end
    resolved
  rescue Errno::ENOENT
    raise ExecutionError, "Working directory does not exist: #{path}"
  end
end
