class ClaudeLocalAdapter < BaseAdapter
  extend TmuxAdapterRunner

  SESSION_PREFIX = "director_run"

  def self.display_name
    "Claude Code (Local)"
  end

  def self.description
    "Run Claude CLI locally with streaming JSON output and session resumption"
  end

  def self.config_schema
    { required: %w[model], optional: %w[max_turns session_id allowed_tools provider base_url working_directory] }
  end

  FORWARDED_ENV_VARS = %w[HOME PATH ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN].freeze

  OLLAMA_DEFAULT_BASE_URL = "http://localhost:11434".freeze

  CLI_COMMON_FLAGS = [
    "--output-format stream-json --verbose",
    "--dangerously-skip-permissions",
    "--setting-sources project,local",
    "--disable-slash-commands"
  ].freeze

  def self.env_flags(column)
    provider = column.adapter_config&.dig("provider").to_s
    provider == "ollama" ? ollama_env_flags(column) : anthropic_env_flags(column)
  end

  def self.anthropic_env_flags(column)
    flags = forward_env_flags(FORWARDED_ENV_VARS)

    { "ANTHROPIC_API_KEY" => %i[anthropic api_key],
      "CLAUDE_CODE_OAUTH_TOKEN" => %i[anthropic oauth_token] }.each do |var, path|
      next if ENV[var].present?
      value = Rails.application.credentials.dig(*path)
      flags << "-e #{var}=#{value.shellescape}" if value.present?
    end

    flags << "-e CLAUDE_CONFIG_DIR=#{agent_config_dir(column).shellescape}"
    flags.join(" ")
  end

  def self.ollama_env_flags(column)
    base_url = column.adapter_config&.dig("base_url").presence || OLLAMA_DEFAULT_BASE_URL

    flags = forward_env_flags(%w[HOME PATH])
    flags << "-e ANTHROPIC_BASE_URL=#{base_url.shellescape}"
    flags << "-e ANTHROPIC_AUTH_TOKEN=ollama"
    flags << "-e ANTHROPIC_API_KEY="
    flags << "-e CLAUDE_CONFIG_DIR=#{agent_config_dir(column).shellescape}"
    flags.join(" ")
  end

  def self.agent_config_dir(column)
    dir = Rails.root.join("tmp", "claude_agent_config", column.id.to_s)
    FileUtils.mkdir_p(dir)
    dir.to_s
  end

  def self.build_agent_command(column:, run:, prompt:, session_id: nil, temp_files:)
    build_claude_command(column, prompt, session_id, temp_files)
  end

  def self.parse_result(accumulated_lines)
    session_id = nil
    cost_cents = nil
    exit_code  = 0
    error_message = nil

    accumulated_lines.each do |line|
      next if line.blank?
      begin
        event = JSON.parse(line)
      rescue JSON::ParserError
        next
      end

      if event["type"] == "assistant" && event["error"] == "authentication_failed"
        raise ExecutionError, "Claude CLI not authenticated. Run `claude /login` to sign in."
      end

      next unless event["type"] == "result"

      session_id = event["session_id"]
      if event["total_cost_usd"].present?
        cost_cents = (event["total_cost_usd"].to_f * 100).round
      end
      if event["subtype"] == "error" || event["is_error"] == true
        exit_code = 1
        error_message = event["result"]
      end
    end

    if session_id.nil? && error_message.nil?
      raise ExecutionError, "Agent process exited without producing a result"
    end

    { exit_code: exit_code, session_id: session_id, cost_cents: cost_cents, error_message: error_message }
  end

  def self.kill_session(name)
    system("tmux kill-session -t #{name.shellescape} 2>/dev/null")
  end

  private_class_method def self.build_claude_command(column, prompt, session_id, temp_files)
    config = column.adapter_config || {}

    parts = [ "claude", "-p" ]
    parts << prompt.to_s.shellescape
    parts.concat(CLI_COMMON_FLAGS)
    parts << "--model #{config['model'].shellescape}" if config["model"].present?
    parts << "--max-turns #{config['max_turns'].to_i}" if config["max_turns"].present?

    mcp_config = build_mcp_config(column, temp_files)
    parts << "--mcp-config #{mcp_config.path.shellescape}" if mcp_config

    allowed = config["allowed_tools"].presence || "mcp__director__*"
    parts << "--allowedTools #{allowed.shellescape}"
    parts << "--resume #{session_id.shellescape}" if session_id.present?
    parts.join(" ")
  end

  private_class_method def self.build_mcp_config(column, temp_files)
    return nil unless column.api_token.present?

    bin_path = Rails.root.join("bin", "director-mcp").to_s
    config = {
      mcpServers: {
        director: {
          command: bin_path,
          env: { "DIRECTOR_API_TOKEN" => column.api_token }
        }
      }
    }

    file = Tempfile.new([ "director_mcp", ".json" ])
    file.write(config.to_json)
    file.flush
    temp_files << file
    file
  end
end
