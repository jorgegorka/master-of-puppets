require "test_helper"

class WorkspaceFileTest < ActiveSupport::TestCase
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

  test "lists a 3-level tree in dirs-first / alpha order" do
    write_tree(
      "memory/a.md"           => "1",
      "memory/zeta.md"        => "1",
      "memory/notes/b.md"     => "2",
      "memory/notes/aaa.md"   => "2",
      "memory/notes/nest/c.md" => "3"
    )

    tree = WorkspaceFile.tree(root: "memory")

    assert_equal %w[notes a.md zeta.md], tree.map(&:name)
    notes = tree.first
    assert notes.directory
    assert_equal %w[nest aaa.md b.md], notes.children.map(&:name)
    nest = notes.children.first
    assert_equal %w[c.md], nest.children.map(&:name)
  end

  test "max_depth truncates beyond the limit" do
    write_tree("memory/a/b/c/d.md" => "x")

    tree = WorkspaceFile.tree(root: "memory", max_depth: 1)
    a    = tree.first

    assert_equal "a", a.name
    # depth 0 -> a, depth 1 -> b, depth 2 (which is max_depth + 1) -> stops
    assert_equal %w[b], a.children.map(&:name)
    assert_empty a.children.first.children
  end

  test "max_entries caps the total node count" do
    files = (1..10).to_h { |i| [ "memory/n#{i}.md", "x" ] }
    write_tree(**files)

    tree = WorkspaceFile.tree(root: "memory", max_entries: 5)

    assert_equal 5, tree.size
  end

  test "default ignore list omits node_modules and .git" do
    write_tree(
      "memory/keep.md"                 => "1",
      "memory/node_modules/lib/a.js"   => "noise",
      "memory/.git/HEAD"               => "ref"
    )

    names = WorkspaceFile.tree(root: "memory").map(&:name)

    assert_includes names, "keep.md"
    refute_includes names, "node_modules"
    refute_includes names, ".git"
  end

  test "symlinks pointing outside the root are skipped" do
    File.write(File.join(@tmp, "memory/inside.md"), "in")
    File.symlink("/etc", File.join(@tmp, "memory/escape"))

    names = WorkspaceFile.tree(root: "memory").map(&:name)

    assert_includes names, "inside.md"
    refute_includes names, "escape"
  end

  private
    def write_tree(files)
      files.each do |rel, body|
        absolute = File.join(@tmp, rel)
        FileUtils.mkdir_p(File.dirname(absolute))
        File.write(absolute, body)
      end
    end
end
