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
end
