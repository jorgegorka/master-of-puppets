require "test_helper"

class CodexAdapterTest < ActiveSupport::TestCase
  setup do
    @role = roles(:developer)
    @role.update!(
      adapter_type: :codex,
      adapter_config: { "model" => "gpt-5-codex" }
    )
    @context = {
      run_id: role_runs(:running_run).id,
      trigger_type: "task_assigned",
      task_id: 42,
      task_title: "Fix login bug",
      task_description: "Users cannot log in"
    }

    CodexAdapter.define_singleton_method(:poll_sleep) { |_n| nil }
  end

  teardown do
    CodexAdapter.singleton_class.remove_method(:poll_sleep) rescue nil
    FileUtils.rm_rf(Rails.root.join("tmp", "codex_agent_config", @role.id.to_s)) rescue nil
  end

  test "display_name returns OpenAI Codex (Local)" do
    assert_equal "OpenAI Codex (Local)", CodexAdapter.display_name
  end

  test "description returns expected text" do
    assert_equal "Run Codex CLI locally with JSON event stream and session resumption", CodexAdapter.description
  end

  test "config_schema requires model" do
    schema = CodexAdapter.config_schema
    assert_includes schema[:required], "model"
    assert_includes schema[:optional], "max_turns"
    assert_includes schema[:optional], "provider"
    assert_includes schema[:optional], "sandbox"
    assert_includes schema[:optional], "approval"
  end

  test "build_codex_command includes default headless flags and model" do
    prompt_file = Tempfile.new([ "prompt", ".txt" ])
    cmd = CodexAdapter.send(:build_codex_command, @role, {}, prompt_file)

    assert_match(/codex exec/, cmd)
    assert_match(/--json/, cmd)
    assert_match(/--skip-git-repo-check/, cmd)
    assert_match(/--sandbox workspace-write/, cmd)
    assert_match(/--ask-for-approval never/, cmd)
    assert_match(/--model gpt-5-codex/, cmd)
    assert_includes cmd, prompt_file.path
    assert_match(/cat .* \| codex exec/, cmd)
    assert cmd.end_with?(" -")
  ensure
    prompt_file.close! rescue nil
  end

  test "build_codex_command includes resume subcommand when resume_session_id present" do
    prompt_file = Tempfile.new([ "prompt", ".txt" ])
    cmd = CodexAdapter.send(:build_codex_command, @role, { resume_session_id: "sess-abc-123" }, prompt_file)

    assert_match(/codex exec resume sess-abc-123/, cmd)
  ensure
    prompt_file.close! rescue nil
  end

  test "build_codex_command honors sandbox and approval overrides" do
    @role.update!(adapter_config: {
      "model" => "gpt-5-codex",
      "sandbox" => "danger-full-access",
      "approval" => "on-failure"
    })
    prompt_file = Tempfile.new([ "prompt", ".txt" ])

    cmd = CodexAdapter.send(:build_codex_command, @role, {}, prompt_file)

    assert_match(/--sandbox danger-full-access/, cmd)
    assert_match(/--ask-for-approval on-failure/, cmd)
  ensure
    prompt_file.close! rescue nil
  end

  test "env_flags forwards OPENAI_API_KEY and sets CODEX_HOME" do
    original = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "sk-openai-test"

    flags = CodexAdapter.env_flags(@role)

    assert_includes flags, "OPENAI_API_KEY=sk-openai-test"
    assert_match(/-e CODEX_HOME=.*codex_agent_config/, flags)
  ensure
    ENV["OPENAI_API_KEY"] = original
  end

  test "env_flags with provider=ollama sets OPENAI_BASE_URL and blanks real keys" do
    original_openai = ENV["OPENAI_API_KEY"]
    original_codex  = ENV["CODEX_API_KEY"]
    ENV["OPENAI_API_KEY"] = "sk-should-not-leak"
    ENV["CODEX_API_KEY"]  = "sk-codex-should-not-leak"

    @role.update!(adapter_config: {
      "model" => "gpt-oss-20b",
      "provider" => "ollama",
      "base_url" => "http://localhost:11434/v1"
    })

    flags = CodexAdapter.env_flags(@role)

    assert_includes flags, "-e OPENAI_BASE_URL=http://localhost:11434/v1"
    assert_includes flags, "-e OPENAI_API_KEY=ollama"
    assert_includes flags, "-e CODEX_API_KEY="
    assert_no_match(/OPENAI_API_KEY=sk-should-not-leak/, flags)
    assert_no_match(/CODEX_API_KEY=sk-codex-should-not-leak/, flags)
    assert_match(/-e CODEX_HOME=/, flags)
  ensure
    ENV["OPENAI_API_KEY"] = original_openai
    ENV["CODEX_API_KEY"]  = original_codex
  end

  test "env_flags with provider=ollama defaults base_url when blank" do
    @role.update!(adapter_config: { "model" => "gpt-oss-20b", "provider" => "ollama" })

    flags = CodexAdapter.env_flags(@role)

    assert_includes flags, "-e OPENAI_BASE_URL=http://localhost:11434/v1"
  end

  test "write_mcp_config! writes config.toml with director server when api_token present" do
    @role.update!(api_token: "test-token-xyz")

    CodexAdapter.send(:write_mcp_config!, @role)

    config_path = File.join(CodexAdapter.send(:agent_codex_home, @role), "config.toml")
    assert File.exist?(config_path)

    contents = File.read(config_path)
    assert_match(/\[mcp_servers\.director\]/, contents)
    assert_match(/DIRECTOR_API_TOKEN = "test-token-xyz"/, contents)
    assert_includes contents, Rails.root.join("bin", "director-mcp").to_s
  end

  test "write_mcp_config! is a no-op when api_token blank" do
    role_without_token = Role.create!(
      title: "Test Role No Token",
      project: projects(:acme),
      role_category: role_categories(:executor),
      api_token: nil,
      adapter_type: nil
    )

    CodexAdapter.send(:write_mcp_config!, role_without_token)

    config_path = File.join(CodexAdapter.send(:agent_codex_home, role_without_token), "config.toml")
    assert_not File.exist?(config_path)
  ensure
    FileUtils.rm_rf(Rails.root.join("tmp", "codex_agent_config", role_without_token.id.to_s)) rescue nil
    role_without_token&.destroy
  end

  test "parse_result extracts session_id from top-level field" do
    lines = [
      '{"type":"session.created","session_id":"sess-xyz-1"}',
      '{"type":"turn.completed"}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal "sess-xyz-1", result[:session_id]
    assert_equal 0, result[:exit_code]
  end

  test "parse_result extracts session_id from nested msg.session_id" do
    lines = [
      '{"type":"session_configured","msg":{"session_id":"sess-nested-2"}}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal "sess-nested-2", result[:session_id]
  end

  test "parse_result converts total_cost_usd to cents" do
    lines = [
      '{"type":"session.created","session_id":"s1"}',
      '{"type":"usage","total_cost_usd":0.05}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal 5, result[:cost_cents]
  end

  test "parse_result converts nested usage.cost_usd to cents" do
    lines = [
      '{"type":"session.created","session_id":"s1"}',
      '{"type":"result","usage":{"cost_usd":0.25}}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal 25, result[:cost_cents]
  end

  test "parse_result returns nil cost when no cost data present" do
    lines = [
      '{"type":"session.created","session_id":"s1"}',
      '{"type":"message","content":"hello"}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_nil result[:cost_cents]
  end

  test "parse_result flags errors via error field" do
    lines = [
      '{"type":"session.created","session_id":"s1"}',
      '{"type":"error","error":{"message":"API key invalid"}}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal 1, result[:exit_code]
    assert_equal "API key invalid", result[:error_message]
  end

  test "parse_result flags errors via plain error string" do
    lines = [
      '{"type":"session.created","session_id":"s1"}',
      '{"type":"error","error":"Something went wrong"}'
    ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal 1, result[:exit_code]
    assert_equal "Something went wrong", result[:error_message]
  end

  test "parse_result raises when no session and no error" do
    lines = [
      '{"type":"message","content":"chatter"}'
    ]

    assert_raises(CodexAdapter::ExecutionError) do
      CodexAdapter.send(:parse_result, lines)
    end
  end

  test "parse_result handles empty and non-json lines" do
    lines = [ "", "  ", "some log noise", '{"type":"session.created","session_id":"s1"}' ]

    result = CodexAdapter.send(:parse_result, lines)

    assert_equal "s1", result[:session_id]
    assert_equal 0, result[:exit_code]
  end

  test "budget_exhausted raises before execution" do
    @role.update!(budget_cents: 100, budget_period_start: Date.current.beginning_of_month)
    @role.assigned_tasks.create!(
      title: "Test task",
      project: projects(:acme),
      cost_cents: 150,
      created_at: Time.current
    )

    assert_raises(CodexAdapter::BudgetExhausted) do
      CodexAdapter.execute(@role, @context)
    end
  end

  test "retryable_error detects stall messages" do
    error = CodexAdapter::ExecutionError.new("Agent stalled: no output")
    assert CodexAdapter.send(:retryable_error?, error)
  end

  test "retryable_error detects result missing messages" do
    error = CodexAdapter::ExecutionError.new("exited without producing a result")
    assert CodexAdapter.send(:retryable_error?, error)
  end
end
