require "test_helper"

class Tool::Internal::WriteFileTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
    @prev = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev
  end

  test "writes a file and round-trips" do
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "memory/note.md", "content" => "hello world" },
      user: users(:one)
    )
    refute result.is_error
    assert_equal "hello world", File.read(File.join(@tmp, "memory/note.md"))
    assert_match(/wrote 11 bytes/, result.output)
  end

  test "creates intermediate directories" do
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "memory/sub/dir/note.md", "content" => "deep" },
      user: users(:one)
    )
    refute result.is_error
    assert_equal "deep", File.read(File.join(@tmp, "memory/sub/dir/note.md"))
  end

  test "rejects traversal" do
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "../../etc/evil", "content" => "x" },
      user: users(:one)
    )
    assert result.is_error
    assert_match(/forbidden/, result.error)
  end

  test "rejects oversize content" do
    big = "x" * (Tool::Internal::WriteFile::MAX_BYTES + 1)
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "memory/big.md", "content" => big },
      user: users(:one)
    )
    assert result.is_error
    assert_match(/too large/, result.error)
  end

  test "cleans up tmp file on rename failure" do
    original = File.method(:rename)
    File.define_singleton_method(:rename) { |*| raise Errno::EXDEV, "fake cross-device" }
    begin
      assert_raises(Errno::EXDEV) do
        Tool::Internal::WriteFile.invoke(
          input: { "path" => "memory/note.md", "content" => "data" },
          user: users(:one)
        )
      end
    ensure
      File.singleton_class.define_method(:rename, original)
    end
    leftovers = Dir.glob(File.join(@tmp, "memory/.*.tmp"))
    assert_empty leftovers
  end
end
