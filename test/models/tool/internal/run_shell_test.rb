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
      result = Tool::Internal::RunShell.invoke(input: { "command" => "sleep 60" }, user: @admin)
      assert result.is_error
      assert_match(/timed out/, result.error)
    end
  end

  test "truncates oversize output" do
    big = "y" * (Tool::Internal::RunShell::MAX_OUTPUT_BYTES + 100)
    fake_status = Object.new
    def fake_status.success?; true; end
    def fake_status.exitstatus; 0; end
    with_singleton_method(Open3, :capture3, ->(_cmd, **_opts) { [ big, "", fake_status ] }) do
      result = Tool::Internal::RunShell.invoke(input: { "command" => "noop" }, user: @admin)
      refute result.is_error
      assert_match(/truncated/, result.output)
    end
  end
end
