require "test_helper"

class Files::NodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    File.write(File.join(@tmp, ".gitignore"), "*.log\n")
    FileUtils.mkdir_p(File.join(@tmp, "skills"))
    File.write(File.join(@tmp, "skills/seed.md"), "seed body")
    @admin  = users(:one)
    @member = users(:member)
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "show returns the body for a file" do
    sign_in_as(@admin)
    get files_node_path(".gitignore")
    assert_response :success
    assert_includes response.body, "*.log"
  end

  test "show on a directory renders the subtree index" do
    sign_in_as(@admin)
    get files_node_path("skills")
    assert_response :success
    assert_includes response.body, "seed.md"
  end

  test "update writes new content" do
    sign_in_as(@admin)
    patch files_node_path("skills/seed.md"), params: { content: "rewritten" }
    assert_redirected_to files_node_path("skills/seed.md")
    assert_equal "rewritten", File.read(File.join(@tmp, "skills/seed.md"))
  end

  test "destroy removes the file" do
    sign_in_as(@admin)
    delete files_node_path("skills/seed.md")
    assert_redirected_to files_path
    refute File.exist?(File.join(@tmp, "skills/seed.md"))
  end

  test "encoded-slash traversal probe stays inside the workspace" do
    # Rack preserves `%2F` inside path segments, so `..%2Fetc%2Fpasswd`
    # is treated as a single (weird) filename, not a directory traversal.
    # The controller resolves it, finds no file at that name, and returns
    # 404 — never reading anything outside `${MOP_HOME}`.
    sign_in_as(@admin)
    get files_node_path("..%2Fetc%2Fpasswd")
    assert_response :not_found
  end

  test "WorkspacePath::EscapeAttempt surfaces as 403, not 500" do
    # Stub WorkspacePath.resolve so any controller-level failure mode that
    # bubbles into `EscapeAttempt` produces the right HTTP response. The
    # path-traversal logic itself is fully covered by WorkspacePathTest;
    # this test is purely about the controller's rescue handler.
    WorkspacePath.singleton_class.alias_method(:__real_resolve, :resolve)
    WorkspacePath.define_singleton_method(:resolve) do |**|
      raise WorkspacePath::EscapeAttempt, "blocked"
    end
    begin
      sign_in_as(@admin)
      get files_node_path("anything")
      assert_response :forbidden
    ensure
      WorkspacePath.singleton_class.alias_method(:resolve, :__real_resolve)
      WorkspacePath.singleton_class.remove_method(:__real_resolve)
    end
  end

  test "non-admin cannot read the workspace" do
    sign_in_as(@member)
    get files_node_path(".gitignore")
    assert_redirected_to root_path
  end

  test "non-admin cannot edit the workspace" do
    sign_in_as(@member)
    patch files_node_path("skills/seed.md"), params: { content: "rooted" }
    assert_redirected_to root_path
    assert_equal "seed body", File.read(File.join(@tmp, "skills/seed.md"))
  end
end
