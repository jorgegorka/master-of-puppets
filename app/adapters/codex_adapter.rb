class CodexAdapter < BaseAdapter
  extend TmuxAdapterRunner

  SESSION_PREFIX = "director_codex"

  def self.display_name
    "OpenAI Codex (Local)"
  end

  def self.description
    "Run Codex CLI locally with JSON event stream and session resumption"
  end

  def self.config_schema
    { required: %w[model], optional: %w[max_turns provider base_url sandbox approval working_directory] }
  end

  FORWARDED_ENV_VARS = %w[HOME PATH OPENAI_API_KEY CODEX_API_KEY].freeze
  OLLAMA_DEFAULT_BASE_URL = "http://localhost:11434/v1".freeze

  CLI_COMMON_FLAGS = [
    "--json",
    "--skip-git-repo-check",
    "--sandbox workspace-write",
    "--ask-for-approval never"
  ].freeze

  def self.env_flags(column)
    provider = column.adapter_config&.dig("provider").to_s
    flags = provider == "ollama" ? ollama_env_flags(column) : openai_env_flags
    flags << "-e CODEX_HOME=#{agent_codex_home(column).shellescape}"
    flags.join(" ")
  end

  def self.openai_env_flags
    flags = forward_env_flags(FORWARDED_ENV_VARS)

    { "OPENAI_API_KEY" => %i[openai api_key],
      "CODEX_API_KEY"  => %i[openai codex_api_key] }.each do |var, path|
      next if ENV[var].present?
      value = Rails.application.credentials.dig(*path)
      flags << "-e #{var}=#{value.shellescape}" if value.present?
    end

    flags
  end

  def self.ollama_env_flags(column)
    base_url = column.adapter_config&.dig("base_url").presence || OLLAMA_DEFAULT_BASE_URL

    flags = forward_env_flags(%w[HOME PATH])
    flags << "-e OPENAI_BASE_URL=#{base_url.shellescape}"
    flags << "-e OPENAI_API_KEY=ollama"
    flags << "-e CODEX_API_KEY="
    flags
  end

  def self.agent_codex_home(column)
    dir = Rails.root.join("tmp", "codex_agent_config", column.id.to_s)
    FileUtils.mkdir_p(dir)
    dir.to_s
  end

  def self.build_agent_command(column:, run:, prompt:, session_id: nil, temp_files:)
    write_mcp_config!(column)
    prompt_file = build_prompt_file(prompt, temp_files)
    build_codex_command(column, prompt_file, session_id)
  end

  def self.parse_result(accumulated_lines)
    session_id = nil
    cost_cents = nil
    exit_code = 0
    error_message = nil

    accumulated_lines.each do |line|
      next if line.blank?
      begin
        event = JSON.parse(line)
      rescue JSON::ParserError
        next
      end

      session_id ||= event["session_id"] ||
                     event.dig("msg", "session_id") ||
                     event.dig("session", "id")

      cost = event["total_cost_usd"] ||
             event.dig("usage", "total_cost_usd") ||
             event.dig("usage", "cost_usd") ||
             event["cost_usd"]
      cost_cents = (cost.to_f * 100).round if cost.present?

      if event["type"].to_s.include?("error") || event["error"].present?
        exit_code = 1
        err = event["error"]
        error_message = (err.is_a?(Hash) ? err["message"] : err) || event["message"]
      end
    end

    if session_id.nil? && error_message.nil?
      raise ExecutionError, "Codex exited without producing a result"
    end

    { exit_code: exit_code, session_id: session_id, cost_cents: cost_cents, error_message: error_message }
  end

  private_class_method def self.build_prompt_file(prompt, temp_files)
    file = Tempfile.new([ "codex_prompt", ".txt" ])
    file.write(prompt.to_s)
    file.flush
    temp_files << file
    file
  end

  private_class_method def self.build_codex_command(column, prompt_file, session_id)
    config = column.adapter_config || {}

    parts = [ "codex", "exec" ]
    parts << "resume #{session_id.shellescape}" if session_id.present?
    parts.concat(CLI_COMMON_FLAGS)
    parts << "--model #{config['model'].shellescape}" if config["model"].present?
    parts << "--sandbox #{config['sandbox'].shellescape}" if config["sandbox"].present?
    parts << "--ask-for-approval #{config['approval'].shellescape}" if config["approval"].present?
    parts << "-"

    "cat #{prompt_file.path.shellescape} | " + parts.join(" ")
  end

  private_class_method def self.write_mcp_config!(column)
    return unless column.api_token.present?

    bin_path = Rails.root.join("bin", "director-mcp").to_s
    toml = <<~TOML
      [mcp_servers.director]
      command = #{bin_path.inspect}

      [mcp_servers.director.env]
      DIRECTOR_API_TOKEN = #{column.api_token.inspect}
    TOML

    File.write(File.join(agent_codex_home(column), "config.toml"), toml)
  end
end
