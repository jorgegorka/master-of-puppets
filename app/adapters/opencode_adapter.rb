class OpencodeAdapter < BaseAdapter
  extend TmuxAdapterRunner

  SESSION_PREFIX = "director_opencode"

  def self.display_name
    "OpenCode"
  end

  def self.description
    "Run OpenCode CLI locally with JSON output"
  end

  def self.config_schema
    { required: %w[model], optional: %w[max_turns working_directory provider base_url] }
  end

  FORWARDED_ENV_VARS = %w[
    HOME PATH
    ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY
    GITHUB_TOKEN GROQ_API_KEY
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
    AZURE_OPENAI_ENDPOINT AZURE_OPENAI_API_KEY AZURE_OPENAI_API_VERSION
    VERTEXAI_PROJECT VERTEXAI_LOCATION LOCAL_ENDPOINT
  ].freeze

  OLLAMA_DEFAULT_BASE_URL = "http://localhost:11434/v1".freeze

  def self.env_flags(column)
    provider = column.adapter_config&.dig("provider").to_s
    provider == "ollama" ? ollama_env_flags(column) : default_env_flags
  end

  def self.default_env_flags
    forward_env_flags(FORWARDED_ENV_VARS).join(" ")
  end

  def self.ollama_env_flags(column)
    base_url = column.adapter_config&.dig("base_url").presence || OLLAMA_DEFAULT_BASE_URL

    flags = forward_env_flags(%w[HOME PATH])
    flags << "-e OPENAI_BASE_URL=#{base_url.shellescape}"
    flags << "-e OPENAI_API_KEY=ollama"
    flags.join(" ")
  end

  def self.build_agent_command(column:, run:, prompt:, session_id: nil, temp_files:)
    prompt_file = build_prompt_file(prompt, temp_files)
    mcp_config  = build_mcp_config(column, temp_files)
    build_opencode_command(column, prompt_file, mcp_config)
  end

  def self.parse_result(accumulated_lines)
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

      if event["cost_usd"].present?
        cost_cents = (event["cost_usd"].to_f * 100).round
      elsif event["total_cost_usd"].present?
        cost_cents = (event["total_cost_usd"].to_f * 100).round
      elsif event["usage"].present? && event["usage"]["cost_usd"].present?
        cost_cents = (event["usage"]["cost_usd"].to_f * 100).round
      end

      if event["error"].present? || event["status"] == "error"
        exit_code = 1
        error_message = event["error"] || event["message"]
      end
    end

    { exit_code: exit_code, cost_cents: cost_cents, error_message: error_message }
  end

  private_class_method def self.build_prompt_file(prompt, temp_files)
    file = Tempfile.new([ "opencode_prompt", ".txt" ])
    file.write(prompt.to_s)
    file.flush
    temp_files << file
    file
  end

  private_class_method def self.build_opencode_command(column, prompt_file, mcp_config)
    config = column.adapter_config || {}

    parts = [ "opencode" ]
    parts << "-f json"
    parts << "-q"
    parts << "-p"
    parts << "$(cat #{prompt_file.path.shellescape})"

    parts << "--model #{config['model'].shellescape}" if config["model"].present?
    parts << "--max-turns #{config['max_turns'].to_i}" if config["max_turns"].present?
    parts << "--mcp-config #{mcp_config.path.shellescape}" if mcp_config

    parts.join(" ")
  end

  private_class_method def self.build_mcp_config(column, temp_files)
    return nil unless column.api_token.present?

    bin_path = Rails.root.join("bin", "director-mcp").to_s
    config = {
      mcpServers: {
        director: {
          type: "stdio",
          command: bin_path,
          env: { "DIRECTOR_API_TOKEN" => column.api_token }
        }
      }
    }

    file = Tempfile.new([ "opencode_mcp", ".json" ])
    file.write(config.to_json)
    file.flush
    temp_files << file
    file
  end
end
