require "test_helper"

class WorkspaceBootstrapTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf(@tmp)
  end

  test "creates the five workspace subdirectories" do
    WorkspaceBootstrap.run(@tmp)
    %w[memory skills profiles artifacts logs].each do |sub|
      assert Pathname.new(@tmp).join(sub).directory?, "expected #{sub}/ to exist"
    end
  end

  test "seeds memory/MEMORY.md only on first run" do
    WorkspaceBootstrap.run(@tmp)
    seed = Pathname.new(@tmp).join("memory/MEMORY.md")
    assert_equal WorkspaceBootstrap::SEED_MEMORY, seed.read

    seed.write("# Edited\n")
    WorkspaceBootstrap.run(@tmp)
    assert_equal "# Edited\n", seed.read, "second run must not clobber an existing MEMORY.md"
  end

  test "is idempotent across repeat runs" do
    2.times { WorkspaceBootstrap.run(@tmp) }
    assert Pathname.new(@tmp).join("memory/MEMORY.md").exist?
  end

  test "copies seed skills into ${MOP_HOME}/skills on first boot" do
    Dir.mktmpdir do |dir|
      WorkspaceBootstrap.run(dir)
      assert File.exist?(File.join(dir, "skills/io/filesystem/SKILL.md")),
        "expected filesystem seed skill to be copied"
      assert File.exist?(File.join(dir, "skills/research/deep_research/SKILL.md")),
        "expected deep_research seed skill to be copied"
    end
  end

  test "does not clobber an edited seed skill on re-boot" do
    Dir.mktmpdir do |dir|
      WorkspaceBootstrap.run(dir)
      edited = File.join(dir, "skills/io/filesystem/SKILL.md")
      File.write(edited, "EDITED CONTENT")
      WorkspaceBootstrap.run(dir)
      assert_equal "EDITED CONTENT", File.read(edited)
    end
  end
end
