require "test_helper"

class Memory::FilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
    @user   = users(:one)
    @member = users(:member)
    sign_in_as(@user)
  end

  teardown do
    MemoryFileFts.connection.execute("DELETE FROM memory_files_fts")
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "create writes a new file and redirects to its edit page" do
    post memory_files_path, params: { path: "note.md", content: "# Note\n\nhello" }

    assert_redirected_to memory_file_path("note.md")
    assert File.exist?(File.join(@tmp, "memory/note.md"))
    assert MemoryFile.find_by(path: "note.md")
  end

  test "show renders the edit page" do
    File.write(File.join(@tmp, "memory/seen.md"), "# Seen\n")
    MemoryFile.reindex("seen.md")

    get memory_file_path("seen.md")

    assert_response :success
    assert_includes response.body, "Seen"
  end

  test "update writes new content" do
    File.write(File.join(@tmp, "memory/edit.md"), "before")
    file = MemoryFile.reindex("edit.md")

    patch memory_file_path(file.path), params: { content: "after" }

    assert_redirected_to memory_file_path(file.path)
    assert_equal "after", File.read(File.join(@tmp, "memory/edit.md"))
    assert_equal Digest::SHA256.hexdigest("after"), file.reload.content_digest
  end

  test "destroy removes the row and the disk file" do
    File.write(File.join(@tmp, "memory/gone.md"), "x")
    MemoryFile.reindex("gone.md")

    delete memory_file_path("gone.md")

    assert_redirected_to memory_path
    refute MemoryFile.exists?(path: "gone.md")
    refute File.exist?(File.join(@tmp, "memory/gone.md"))
  end

  test "show on an unknown path is a 404" do
    get memory_file_path("nope.md")
    assert_response :not_found
  end

  test "create rejects a path that escapes the workspace" do
    post memory_files_path, params: { path: "../../etc/passwd", content: "rooted" }

    assert_response :forbidden
    refute File.exist?(File.join(@tmp, "etc/passwd"))
    # Path resolution must happen before the row is persisted — a rejected
    # write must not leave an orphan MemoryFile behind.
    refute MemoryFile.exists?(path: "../../etc/passwd")
  end

  test "update with a path-traversal id never reaches the disk" do
    patch memory_file_path("..%2Fetc%2Fpasswd"), params: { content: "rooted" }
    assert_response :not_found
    refute File.exist?("/etc/passwd.tmp")
  end

  test "non-admin cannot create" do
    sign_in_as(@member)
    post memory_files_path, params: { path: "leak.md", content: "x" }
    assert_redirected_to root_path
    refute File.exist?(File.join(@tmp, "memory/leak.md"))
    refute MemoryFile.exists?(path: "leak.md")
  end

  test "non-admin cannot update" do
    File.write(File.join(@tmp, "memory/admin.md"), "before")
    MemoryFile.reindex("admin.md")
    sign_in_as(@member)
    patch memory_file_path("admin.md"), params: { content: "after" }
    assert_redirected_to root_path
    assert_equal "before", File.read(File.join(@tmp, "memory/admin.md"))
  end
end
