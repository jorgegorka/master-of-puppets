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
    with_singleton_method(File, :rename, ->(*) { raise Errno::EXDEV, "fake cross-device" }) do
      result = Tool::Internal::WriteFile.invoke(
        input: { "path" => "memory/note.md", "content" => "data" },
        user: users(:one)
      )
      assert result.is_error
      assert_match(/write failed/, result.error)
    end
    leftovers = Dir.glob(File.join(@tmp, "memory/.*.tmp"))
    assert_empty leftovers
  end

  test "returns failure (not raise) on rename system error" do
    with_singleton_method(File, :rename, ->(_a, _b) { raise Errno::EXDEV }) do
      result = Tool::Internal::WriteFile.invoke(
        input: { "path" => "memory/x.md", "content" => "hi" },
        user: users(:one)
      )
      assert result.is_error
      assert_match(/write failed/, result.error)
    end
  end

  test "writing to existing path without overwrite returns failure and leaves original bytes untouched" do
    target = File.join(@tmp, "memory/existing.md")
    File.write(target, "original bytes")
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "memory/existing.md", "content" => "replacement" },
      user: users(:one)
    )
    assert result.is_error
    assert_match(/file exists/, result.error)
    assert_equal "original bytes", File.read(target)
  end

  test "writing with overwrite: true replaces the file" do
    target = File.join(@tmp, "memory/existing.md")
    File.write(target, "original bytes")
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "memory/existing.md", "content" => "replacement", "overwrite" => true },
      user: users(:one)
    )
    refute result.is_error
    assert_equal "replacement", File.read(target)
  end

  # Skills and profiles are org-wide source-of-truth files — their bodies are
  # spliced into the system prompt for every user with that skill enabled. A
  # non-admin must not be able to mint or overwrite one via the model.
  test "refuses to write under skills/ unless the user is admin" do
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "skills/io/filesystem/SKILL.md", "content" => "---\nname: x\n---\nbody" },
      user: users(:member)
    )
    assert result.is_error
    assert_match(/admin/i, result.error)
    refute File.exist?(File.join(@tmp, "skills/io/filesystem/SKILL.md"))
  end

  test "refuses to write under profiles/ unless the user is admin" do
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "profiles/default.yml", "content" => "x" },
      user: users(:member)
    )
    assert result.is_error
    assert_match(/admin/i, result.error)
    refute File.exist?(File.join(@tmp, "profiles/default.yml"))
  end

  test "admins may write under skills/" do
    result = Tool::Internal::WriteFile.invoke(
      input: { "path" => "skills/io/custom/SKILL.md", "content" => "---\nname: custom\n---\nbody" },
      user: users(:one)
    )
    refute result.is_error
    assert File.exist?(File.join(@tmp, "skills/io/custom/SKILL.md"))
  end
end
