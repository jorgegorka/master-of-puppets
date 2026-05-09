require "test_helper"

class OpencodeAdapterTest < ActiveSupport::TestCase
  setup do
    @role = roles(:developer)
    @role.update!(
      adapter_type: :opencode,
      adapter_config: { "model" => "claude-sonnet-4-20250514" }
    )
    @context = {
      run_id: role_runs(:running_run).id,
      trigger_type: "task_assigned",
      task_id: 42,
      task_title: "Fix login bug",
      task_description: "Users cannot log in"
    }

    OpencodeAdapter.define_singleton_method(:poll_sleep) { |_n| nil }
  end

  teardown do
    OpencodeAdapter.singleton_class.remove_method(:poll_sleep) rescue nil
  end

  test "display_name returns OpenCode" do
    assert_equal "OpenCode", OpencodeAdapter.display_name
  end

  test "description returns expected text" do
    assert_equal "Run OpenCode CLI locally with JSON output", OpencodeAdapter.description
  end

  test "config_schema requires model" do
    schema = OpencodeAdapter.config_schema
    assert_includes schema[:required], "model"
    assert_includes schema[:optional], "max_turns"
    assert_includes schema[:optional], "working_directory"
  end

  test "execute includes model in command" do
    prompt_file = Tempfile.new([ "prompt", ".txt" ])
    cmd = OpencodeAdapter.send(:build_opencode_command, @role, prompt_file, nil)
    assert_match /--model claude-sonnet-4-20250514/, cmd
  ensure
    prompt_file.close! rescue nil
  end

  test "execute includes max_turns when configured" do
    @role.update!(adapter_config: { "model" => "claude-sonnet-4-20250514", "max_turns" => 50 })
    prompt_file = Tempfile.new([ "prompt", ".txt" ])
    cmd = OpencodeAdapter.send(:build_opencode_command, @role, prompt_file, nil)
    assert_match /--max-turns 50/, cmd
  ensure
    prompt_file.close! rescue nil
  end

  test "execute parses json output and extracts cost from cost_usd" do
    lines = [
      '{"type":"message","content":"Starting task"}',
      '{"type":"result","cost_usd":0.05,"status":"success"}'
    ]

    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 0, result[:exit_code]
    assert_equal 5, result[:cost_cents]
  end

  test "execute parses total_cost_usd as alternative cost field" do
    lines = [
      '{"type":"result","total_cost_usd":0.123}'
    ]

    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 12, result[:cost_cents]
  end

  test "execute parses usage.cost_usd as nested cost field" do
    lines = [
      '{"type":"result","usage":{"cost_usd":0.25}}'
    ]

    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 25, result[:cost_cents]
  end

  test "execute returns nil cost when no cost data present" do
    lines = [
      '{"type":"message","content":"Hello"}'
    ]

    result = OpencodeAdapter.send(:parse_result, lines)

    assert_nil result[:cost_cents]
  end

  test "execute sets error exit code on error status" do
    lines = [
      '{"type":"result","status":"error","error":"API key invalid"}'
    ]

    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 1, result[:exit_code]
    assert_equal "API key invalid", result[:error_message]
  end

  test "execute sets error exit code on error field" do
    lines = [
      '{"type":"result","error":"Something went wrong"}'
    ]

    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 1, result[:exit_code]
    assert_equal "Something went wrong", result[:error_message]
  end

  test "build_user_prompt includes task details when task assigned" do
    prompt = @role.build_user_prompt(@context)

    assert_includes prompt, "Task #42"
    assert_includes prompt, "Fix login bug"
    assert_includes prompt, "Users cannot log in"
  end

  test "build_user_prompt includes task details when task has context" do
    context = {
      task_id: 1,
      task_title: "Improve Performance",
      task_description: "Make the app faster"
    }
    prompt = @role.build_user_prompt(context)

    assert_includes prompt, "Improve Performance"
    assert_includes prompt, "Make the app faster"
  end

  test "build_user_prompt includes active subtasks when root task has subtasks" do
    context = {
      task_id: 1,
      task_title: "Improve Performance",
      active_subtasks: [
        { id: 10, title: "Optimize queries", status: "in_progress" },
        { id: 11, title: "Add caching", status: "pending" }
      ]
    }
    prompt = @role.build_user_prompt(context)

    assert_includes prompt, "Task #10: Optimize queries (in_progress)"
    assert_includes prompt, "Task #11: Add caching (pending)"
  end

  test "build_user_prompt for task pending review" do
    context = {
      trigger_type: "task_pending_review",
      task_id: 42,
      task_title: "Fix bug",
      assignee_role_title: "Developer"
    }
    prompt = @role.build_user_prompt(context)

    assert_includes prompt, "pending your review"
    assert_includes prompt, "Developer has submitted"
  end

  test "budget_exhausted raises before execution" do
    @role.update!(budget_cents: 100, budget_period_start: Date.current.beginning_of_month)
    # Create a task to simulate spending
    @role.assigned_tasks.create!(
      title: "Test task",
      project: projects(:acme),
      cost_cents: 150,
      created_at: Time.current
    )

    assert_raises(OpencodeAdapter::BudgetExhausted) do
      OpencodeAdapter.execute(@role, @context)
    end
  end

  test "mcp config generated when api_token present" do
    @role.update!(api_token: "test-token-123")
    temp_files = []

    file = OpencodeAdapter.send(:build_mcp_config, @role, temp_files)

    assert file.present?
    file.rewind
    config = JSON.parse(file.read)
    assert_equal "test-token-123", config["mcpServers"]["director"]["env"]["DIRECTOR_API_TOKEN"]
    assert_equal Rails.root.join("bin", "director-mcp").to_s, config["mcpServers"]["director"]["command"]
    assert_equal "stdio", config["mcpServers"]["director"]["type"]
  ensure
    temp_files.each { |f| f.close! rescue nil }
  end

  test "mcp config returns nil when no api_token" do
    @role_without_token = Role.create!(
      title: "Test Role No Token",
      project: projects(:acme),
      role_category: role_categories(:executor),
      api_token: nil,
      adapter_type: nil
    )
    temp_files = []

    file = OpencodeAdapter.send(:build_mcp_config, @role_without_token, temp_files)

    assert_nil file
  ensure
    @role_without_token&.destroy
  end

  test "build_opencode_command includes mcp config when present" do
    mcp_file = Tempfile.new([ "mcp", ".json" ])
    mcp_file.write("{}")
    mcp_file.flush

    prompt_file = Tempfile.new([ "prompt", ".txt" ])
    cmd = OpencodeAdapter.send(:build_opencode_command, @role, prompt_file, mcp_file)

    assert_match /--mcp-config/, cmd
    assert_includes cmd, mcp_file.path
  ensure
    mcp_file.close! rescue nil
    prompt_file.close! rescue nil
  end

  test "build_opencode_command includes all flags" do
    @role.update!(adapter_config: { "model" => "gpt-4o", "max_turns" => 30 })
    prompt_file = Tempfile.new([ "prompt", ".txt" ])

    cmd = OpencodeAdapter.send(:build_opencode_command, @role, prompt_file, nil)

    assert_match /opencode/, cmd
    assert_match /-f json/, cmd
    assert_match /-q/, cmd
    assert_match /--model gpt-4o/, cmd
    assert_match /--max-turns 30/, cmd
    assert_includes cmd, prompt_file.path
  ensure
    prompt_file.close! rescue nil
  end

  test "resolve_working_directory returns nil when blank" do
    result = OpencodeAdapter.send(:resolve_working_directory, nil)
    assert_nil result

    result = OpencodeAdapter.send(:resolve_working_directory, "")
    assert_nil result
  end

  test "resolve_working_directory raises when path does not exist" do
    assert_raises(OpencodeAdapter::ExecutionError) do
      OpencodeAdapter.send(:resolve_working_directory, "/nonexistent/path/12345")
    end
  end

  test "resolve_working_directory raises when path is not a directory" do
    assert_raises(OpencodeAdapter::ExecutionError) do
      OpencodeAdapter.send(:resolve_working_directory, "/etc/hosts")
    end
  end

  test "resolve_working_directory returns expanded path for valid directory" do
    result = OpencodeAdapter.send(:resolve_working_directory, "/tmp")
    # macOS uses /private/tmp, Linux uses /tmp
    assert result.end_with?("/tmp")
    assert File.directory?(result)
  end

  test "parse_result handles empty lines" do
    lines = [ "", "   ", '{"type":"result"}' ]
    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 0, result[:exit_code]
  end

  test "parse_result handles non-json lines" do
    lines = [ "some log output", '{"type":"result"}', "more logs" ]
    result = OpencodeAdapter.send(:parse_result, lines)

    assert_equal 0, result[:exit_code]
  end

  test "env_flags forwards relevant environment variables" do
    original_anthropic = ENV["ANTHROPIC_API_KEY"]
    original_openai = ENV["OPENAI_API_KEY"]

    ENV["ANTHROPIC_API_KEY"] = "sk-ant-123"
    ENV["OPENAI_API_KEY"] = "sk-openai-456"

    flags = OpencodeAdapter.env_flags(@role)

    assert_includes flags, "ANTHROPIC_API_KEY=sk-ant-123"
    assert_includes flags, "OPENAI_API_KEY=sk-openai-456"
  ensure
    ENV["ANTHROPIC_API_KEY"] = original_anthropic
    ENV["OPENAI_API_KEY"] = original_openai
  end

  test "env_flags includes HOME and PATH when present" do
    flags = OpencodeAdapter.env_flags(@role)

    assert_includes flags, "HOME=" if ENV["HOME"].present?
    assert_includes flags, "PATH=" if ENV["PATH"].present?
  end

  test "env_flags with provider=ollama emits OPENAI_BASE_URL and OPENAI_API_KEY=ollama" do
    original_openai = ENV["OPENAI_API_KEY"]
    original_anthropic = ENV["ANTHROPIC_API_KEY"]
    ENV["OPENAI_API_KEY"] = "sk-should-not-leak"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-should-not-leak"

    @role.update!(adapter_config: {
      "model" => "openai/qwen3-coder",
      "provider" => "ollama",
      "base_url" => "http://localhost:11434/v1"
    })

    flags = OpencodeAdapter.env_flags(@role)

    assert_includes flags, "-e OPENAI_BASE_URL=http://localhost:11434/v1"
    assert_includes flags, "-e OPENAI_API_KEY=ollama"
    assert_no_match(/OPENAI_API_KEY=sk-should-not-leak/, flags)
    assert_no_match(/ANTHROPIC_API_KEY=sk-ant-should-not-leak/, flags)
    assert_includes flags, "-e HOME="
  ensure
    ENV["OPENAI_API_KEY"] = original_openai
    ENV["ANTHROPIC_API_KEY"] = original_anthropic
  end

  test "env_flags with provider=ollama defaults base_url when blank" do
    @role.update!(adapter_config: { "model" => "openai/llama3.1", "provider" => "ollama" })

    flags = OpencodeAdapter.env_flags(@role)

    assert_includes flags, "-e OPENAI_BASE_URL=http://localhost:11434/v1"
  end

  test "retryable_error detects stall messages" do
    error = OpencodeAdapter::ExecutionError.new("Agent stalled: no output")
    assert OpencodeAdapter.send(:retryable_error?, error)
  end

  test "retryable_error detects result missing messages" do
    error = OpencodeAdapter::ExecutionError.new("exited without producing a result")
    assert OpencodeAdapter.send(:retryable_error?, error)
  end

  test "retryable_error returns false for other errors" do
    error = OpencodeAdapter::ExecutionError.new("Connection refused")
    assert_not OpencodeAdapter.send(:retryable_error?, error)
  end
end
