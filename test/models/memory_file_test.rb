require "test_helper"

class MemoryFileTest < ActiveSupport::TestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "path is required and unique" do
    body = "# Hello\n"
    File.write(File.join(@tmp, "memory/hello.md"), body)
    MemoryFile.create!(
      path: "hello.md",
      title: "Hello",
      content_digest: Digest::SHA256.hexdigest(body),
      byte_size: body.bytesize,
      disk_mtime: Time.current
    )

    dup = MemoryFile.new(
      path: "hello.md",
      content_digest: "x",
      byte_size: 1,
      disk_mtime: Time.current
    )
    refute dup.valid?
    assert_includes dup.errors[:path], "has already been taken"
  end

  test "body reads from the workspace" do
    body = "# A\n"
    File.write(File.join(@tmp, "memory/a.md"), body)
    file = MemoryFile.create!(
      path: "a.md",
      content_digest: Digest::SHA256.hexdigest(body),
      byte_size: body.bytesize,
      disk_mtime: Time.current
    )
    assert_equal body, file.body
  end

  test "workspace_path refuses traversal" do
    file = MemoryFile.new(path: "../escape")
    assert_raises(WorkspacePath::EscapeAttempt) { file.workspace_path }
  end

  test "recently_changed scope orders by disk_mtime desc" do
    File.write(File.join(@tmp, "memory/older.md"), "old")
    File.write(File.join(@tmp, "memory/newer.md"), "new")
    older = MemoryFile.create!(path: "older.md", content_digest: "a", byte_size: 3, disk_mtime: 2.days.ago)
    newer = MemoryFile.create!(path: "newer.md", content_digest: "b", byte_size: 3, disk_mtime: 1.hour.ago)
    assert_equal [ newer, older ], MemoryFile.recently_changed.where(id: [ older.id, newer.id ]).to_a
  end
end
