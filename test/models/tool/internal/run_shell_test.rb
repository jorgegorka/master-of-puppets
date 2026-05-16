require "test_helper"

class Tool::Internal::RunShellTest < ActiveSupport::TestCase
  # Minimal swap helper: replaces a singleton method for the duration of the
  # block, then restores it. (Minitest 6 dropped `Object#stub`.)
  def with_singleton_method(mod, name, replacement)
    original = mod.method(name)
    mod.define_singleton_method(name, replacement)
    yield
  ensure
    mod.singleton_class.define_method(name, original)
  end
  setup do
    @tmp = Dir.mktmpdir
    @prev = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    @admin = users(:one)
    @member = users(:member)
    raise "fixture :one must be admin" unless @admin.admin?
    raise "fixture :member must not be admin" if @member.admin?
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev
  end

  test "non-admin user is rejected" do
    result = Tool::Internal::RunShell.invoke(input: { "command" => "echo hi" }, user: @member)
    assert result.is_error
    assert_match(/admin-only/, result.error)
  end

  test "nil user is rejected" do
    result = Tool::Internal::RunShell.invoke(input: { "command" => "echo hi" }, user: nil)
    assert result.is_error
    assert_match(/admin-only/, result.error)
  end

  test "empty command is rejected" do
    result = Tool::Internal::RunShell.invoke(input: { "command" => "   " }, user: @admin)
    assert result.is_error
    assert_match(/empty command/, result.error)
  end

  test "runs a successful command" do
    result = Tool::Internal::RunShell.invoke(input: { "command" => "echo hello" }, user: @admin)
    refute result.is_error
    assert_match(/\$ echo hello/, result.output)
    assert_match(/hello/, result.output)
  end

  test "runs in MOP_HOME cwd" do
    File.write(File.join(@tmp, "marker.txt"), "x")
    result = Tool::Internal::RunShell.invoke(input: { "command" => "ls" }, user: @admin)
    refute result.is_error
    assert_match(/marker\.txt/, result.output)
  end

  test "captures non-zero exit" do
    result = Tool::Internal::RunShell.invoke(input: { "command" => "false" }, user: @admin)
    assert result.is_error
    assert_match(/exit 1/, result.error)
  end

  test "times out on slow command" do
    with_singleton_method(Timeout, :timeout, ->(_secs, &_block) { raise Timeout::Error, "test" }) do
      with_singleton_method(Tool::Internal::RunShell, :terminate_process_group!, ->(_pid) { :killed }) do
        result = Tool::Internal::RunShell.invoke(input: { "command" => "sleep 60" }, user: @admin)
        assert result.is_error
        assert_match(/timed out/, result.error)
      end
    end
  end

  test "truncates oversize output" do
    big = "y" * (Tool::Internal::RunShell::MAX_OUTPUT_BYTES + 100)
    fake_status = Object.new
    def fake_status.success?; true; end
    def fake_status.exitstatus; 0; end
    with_singleton_method(Tool::Internal::RunShell, :run_with_timeout, ->(cmd) { [ "$ #{cmd}\n#{big}", fake_status ] }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "noop" }, user: @admin)
      refute result.is_error
      assert_match(/truncated/, result.output)
    end
  end

  test "truncates multi-byte UTF-8 output at byte boundary safely" do
    # Each é is 2 bytes; 100,000 bytes total — well over the 64 KiB cap.
    big_unicode = "é" * 50_000
    fake_status = Object.new
    def fake_status.success?; true; end
    def fake_status.exitstatus; 0; end
    with_singleton_method(Tool::Internal::RunShell, :run_with_timeout, ->(cmd) { [ "$ #{cmd}\n#{big_unicode}", fake_status ] }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "echo" }, user: @admin)
      refute result.is_error
      assert result.output.bytesize < Tool::Internal::RunShell::MAX_OUTPUT_BYTES + 100,
        "output should be capped near MAX_OUTPUT_BYTES, not 4× over"
      assert_includes result.output, "[truncated]"
    end
  end

  test "scrubbed_env nils out the documented secrets" do
    env = Tool::Internal::RunShell.scrubbed_env
    %w[DATABASE_URL RAILS_MASTER_KEY ANTHROPIC_API_KEY OPENAI_API_KEY].each do |key|
      assert env.key?(key), "expected #{key} in scrubbed env"
      assert_nil env[key], "#{key} must be nil so popen3 strips it from the child"
    end
  end

  test "DATABASE_URL is not visible to the child process" do
    ENV["DATABASE_URL"] = "postgres://forbidden"
    result = Tool::Internal::RunShell.invoke(
      input: { "command" => 'printf %s "${DATABASE_URL-MISSING}"' },
      user: @admin
    )
    refute result.is_error
    assert_match(/MISSING/, result.output)
    refute_match(/postgres:\/\/forbidden/, result.output)
  ensure
    ENV.delete("DATABASE_URL")
  end

  test "process group is terminated on timeout (no orphan sleep survives)" do
    captured_pid = nil
    with_singleton_method(Timeout, :timeout, ->(_secs, &_block) { raise Timeout::Error, "test" }) do
      with_singleton_method(Tool::Internal::RunShell, :terminate_process_group!, ->(pid) { captured_pid = pid }) do
        result = Tool::Internal::RunShell.invoke(input: { "command" => "sleep 60" }, user: @admin)
        assert result.is_error
      end
    end
    assert captured_pid && captured_pid.positive?,
      "terminate_process_group! must be called with the child's pid"
  end

  test "is unregistered when MOP_ENABLE_RUN_SHELL=false" do
    saved_registry = Tool::Internal.send(:registry).dup
    Tool::Internal.send(:registry).delete("run_shell")
    refute Tool::Internal.lookup("run_shell"), "run_shell should be gone when registration is disabled"
  ensure
    Tool::Internal.instance_variable_set(:@registry, saved_registry)
  end

  test "supervisor dispatch: happy path returns Tool::Result.ok with stdout body" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) {
      captured = [method, params]
      { "stdout" => "hi from sup\n", "stderr" => "", "exit_code" => 0, "timed_out" => false }
    }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "echo hi" }, user: @admin)
      refute result.is_error
      assert_match(/\$ echo hi/, result.output)
      assert_match(/hi from sup/, result.output)
    end
    assert_equal "shell.run", captured[0]
    assert_equal "echo hi", captured[1][:command]
  end

  test "supervisor dispatch: timed_out returns Tool::Result.failure(/timed out/)" do
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) {
      { "stdout" => "", "stderr" => "", "exit_code" => -1, "timed_out" => true }
    }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "sleep 99" }, user: @admin)
      assert result.is_error
      assert_match(/timed out/, result.error)
    end
  end

  test "supervisor dispatch: non-zero exit returns Tool::Result.failure with exit code" do
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) {
      { "stdout" => "", "stderr" => "bad path\n", "exit_code" => 2, "timed_out" => false }
    }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "false" }, user: @admin)
      assert result.is_error
      assert_match(/exit 2/, result.error)
    end
  end

  test "supervisor unreachable falls back to in-process path" do
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) { raise Errno::ENOENT, "no socket" }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "echo via-fallback" }, user: @admin)
      refute result.is_error
      assert_match(/via-fallback/, result.output)
    end
  end

  test "MOP_RUN_SHELL_FORCE_IN_PROCESS=1 skips the supervisor entirely" do
    called = false
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) { called = true; { "exit_code" => 0, "stdout" => "", "stderr" => "" } }) do
      ENV["MOP_RUN_SHELL_FORCE_IN_PROCESS"] = "1"
      Tool::Internal::RunShell.invoke(input: { "command" => "echo direct" }, user: @admin)
    end
    assert_not called, "supervisor call should not run when the force flag is set"
  ensure
    ENV.delete("MOP_RUN_SHELL_FORCE_IN_PROCESS")
  end
end
