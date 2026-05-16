require "test_helper"

class Tool::Internal::ListDirTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
    @prev = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory/sub"))
    File.write(File.join(@tmp, "memory/a.md"), "alpha")
    File.write(File.join(@tmp, "memory/b.md"), "beta")
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev
  end

  test "lists directory contents (one level)" do
    result = Tool::Internal::ListDir.invoke(input: { "path" => "memory" }, user: users(:one))
    refute result.is_error
    lines = result.output.split("\n")
    assert lines.any? { |l| l.start_with?("dir\t-\tsub") }
    assert lines.any? { |l| l.start_with?("file\t5\ta.md") }
    assert lines.any? { |l| l.start_with?("file\t4\tb.md") }
  end

  test "lists root with empty path" do
    result = Tool::Internal::ListDir.invoke(input: { "path" => "" }, user: users(:one))
    refute result.is_error
    assert_match(/memory/, result.output)
  end

  test "rejects traversal" do
    result = Tool::Internal::ListDir.invoke(input: { "path" => "../../etc" }, user: users(:one))
    assert result.is_error
    assert_match(/forbidden/, result.error)
  end

  test "rejects non-directory" do
    result = Tool::Internal::ListDir.invoke(input: { "path" => "memory/a.md" }, user: users(:one))
    assert result.is_error
    assert_match(/not a directory/, result.error)
  end
end
