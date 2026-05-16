require "test_helper"

class WorkspacePathTest < ActiveSupport::TestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory/notes"))
    File.write(File.join(@tmp, "memory/notes/a.md"), "hi")
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "resolves a clean path under root" do
    path = WorkspacePath.resolve(root: "memory", raw: "notes/a.md")
    assert_equal File.realpath(File.join(@tmp, "memory/notes/a.md")), path.to_s
  end

  test "rel returns path relative to the named root" do
    path = WorkspacePath.resolve(root: "memory", raw: "notes/a.md")
    assert_equal "notes/a.md", path.rel
  end

  test "resolves a not-yet-existing path under root" do
    path = WorkspacePath.resolve(root: "memory", raw: "notes/new.md")
    assert_equal File.realpath(File.join(@tmp, "memory/notes")) + "/new.md", path.to_s
    refute path.exist?
  end

  test "refuses traversal via .." do
    assert_raises(WorkspacePath::EscapeAttempt) do
      WorkspacePath.resolve(root: "memory", raw: "../../../etc/passwd")
    end
  end

  test "refuses absolute paths" do
    assert_raises(WorkspacePath::EscapeAttempt) do
      WorkspacePath.resolve(root: "memory", raw: "/etc/passwd")
    end
  end

  test "refuses null byte injection" do
    assert_raises(WorkspacePath::EscapeAttempt) do
      WorkspacePath.resolve(root: "memory", raw: "notes/a.md\0/etc/passwd")
    end
  end

  test "refuses Windows-style backslashes that would escape" do
    assert_raises(WorkspacePath::EscapeAttempt) do
      WorkspacePath.resolve(root: "memory", raw: "..\\..\\etc")
    end
  end

  test "refuses symlinks that point outside the root" do
    File.symlink("/etc", File.join(@tmp, "memory/escape"))
    assert_raises(WorkspacePath::EscapeAttempt) do
      WorkspacePath.resolve(root: "memory", raw: "escape/passwd")
    end
  end

  test "to_pathname returns a Pathname and read returns the body" do
    path = WorkspacePath.resolve(root: "memory", raw: "notes/a.md")
    assert_kind_of Pathname, path.to_pathname
    assert_equal "hi", path.read
  end
end
