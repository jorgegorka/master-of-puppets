require "test_helper"

class Tool::Internal::ReadFileTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
    @prev = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
    File.write(File.join(@tmp, "memory/a.md"), "hello")
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev
  end

  test "reads a file" do
    result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory/a.md" }, user: users(:one))
    refute result.is_error
    assert_equal "hello", result.output
  end

  test "rejects traversal" do
    result = Tool::Internal::ReadFile.invoke(input: { "path" => "../../etc/passwd" }, user: users(:one))
    assert result.is_error
    assert_match(/forbidden/, result.error)
  end

  test "rejects oversize file" do
    File.write(File.join(@tmp, "memory/big.md"), "x" * (Tool::Internal::ReadFile::MAX_BYTES + 1))
    result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory/big.md" }, user: users(:one))
    assert result.is_error
    assert_match(/max/, result.error)
  end

  test "rejects a directory" do
    result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory" }, user: users(:one))
    assert result.is_error
    assert_match(/directory/, result.error)
  end

  test "rejects missing file" do
    result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory/missing.md" }, user: users(:one))
    assert result.is_error
    assert_match(/not found/, result.error)
  end
end
