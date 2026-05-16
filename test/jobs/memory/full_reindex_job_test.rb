require "test_helper"

class Memory::FullReindexJobTest < ActiveJob::TestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
  end

  teardown do
    MemoryFileFts.connection.execute("DELETE FROM memory_files_fts")
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "perform indexes every .md file under the memory root" do
    File.write(File.join(@tmp, "memory/a.md"), "# A\nfoo")
    FileUtils.mkdir_p(File.join(@tmp, "memory/nested"))
    File.write(File.join(@tmp, "memory/nested/b.md"), "# B\nbar")

    Memory::FullReindexJob.new.perform

    assert MemoryFile.exists?(path: "a.md")
    assert MemoryFile.exists?(path: "nested/b.md")
  end

  test "perform tombstones rows for files that vanished from disk" do
    # Need at least one surviving file on disk: reindex_all defensively skips
    # the bulk tombstone branch when the disk walk turns up zero markdown
    # files (so a transient empty disk can't nuke every row on cold start).
    # Orphan reaping for the all-deleted case is delegated to the per-path
    # watcher events.
    File.write(File.join(@tmp, "memory/keep.md"),  "# Keep\n")
    File.write(File.join(@tmp, "memory/ghost.md"), "x")
    MemoryFile.reindex("keep.md")
    MemoryFile.reindex("ghost.md")
    File.delete(File.join(@tmp, "memory/ghost.md"))

    Memory::FullReindexJob.new.perform

    refute MemoryFile.exists?(path: "ghost.md")
    assert MemoryFile.exists?(path: "keep.md")
  end
end
