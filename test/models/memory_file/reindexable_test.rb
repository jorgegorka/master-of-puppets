require "test_helper"

class MemoryFile::ReindexableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "reindex! populates metadata, FTS row, and tracks an event" do
    body = "# Hello world\n\nsome notes with #tag-one and #tag-two"
    write_memory("hello.md", body)

    file = nil
    assert_difference -> { Event.where(action: "memory_file_reindexed").count }, +1 do
      file = MemoryFile.reindex("hello.md")
    end

    assert_equal "Hello world",                       file.title
    assert_equal %w[tag-one tag-two],                 file.tags
    assert_equal Digest::SHA256.hexdigest(body),      file.content_digest
    assert_equal body.bytesize,                       file.byte_size
    assert_equal 1, fts_count_for(file.id)
  end

  test "reindex! on a deleted file destroys the row and clears its FTS entry" do
    body = "# Bye\n"
    write_memory("bye.md", body)
    file = MemoryFile.reindex("bye.md")

    File.delete(File.join(@tmp, "memory/bye.md"))
    file.reindex!

    refute MemoryFile.exists?(file.id)
    assert_equal 0, fts_count_for(file.id)
  end

  test "reindex! is idempotent when the digest is unchanged" do
    body = "# Stable\n"
    write_memory("stable.md", body)
    file  = MemoryFile.reindex("stable.md")
    rowid = fts_rowid_for(file.id)

    assert_no_difference -> { Event.where(action: "memory_file_reindexed").count } do
      MemoryFile.reindex("stable.md")
    end
    assert_equal rowid, fts_rowid_for(file.id)
  end

  test "reindex_all does not tombstone existing rows when the memory tree is empty" do
    # Same defensive guard as Skill::Loadable — an empty walk must not be read
    # as "all rows are stale". Phase 3 reaches this on every cold start via
    # Memory::FullReindexJob, so a transient empty disk would otherwise nuke
    # every memory row + FTS entry.
    write_memory("here.md", "# Here\n")
    file = MemoryFile.reindex("here.md")
    File.delete(File.join(@tmp, "memory/here.md"))
    Dir.glob(File.join(@tmp, "memory/*")).each { |p| File.delete(p) if File.file?(p) }

    paths = MemoryFile.reindex_all
    assert_empty paths
    assert MemoryFile.exists?(file.id), "must not destroy rows when disk walk is empty"
  end

  test "reindex_all walks the tree, refreshes changes, and tombstones missing files" do
    write_memory("a.md",        "# A\n")
    write_memory("nested/b.md", "# B\n")
    MemoryFile.reindex_all

    assert_equal %w[a.md nested/b.md].sort, MemoryFile.pluck(:path).sort

    File.write(File.join(@tmp, "memory/a.md"), "# A updated\n")
    File.delete(File.join(@tmp, "memory/nested/b.md"))
    MemoryFile.reindex_all

    a = MemoryFile.find_by!(path: "a.md")
    assert_equal "A updated", a.title
    refute MemoryFile.exists?(path: "nested/b.md")
  end

  test "reindex_later enqueues Memory::IndexerJob with the path" do
    assert_enqueued_with(job: Memory::IndexerJob, args: [ "foo.md" ]) do
      MemoryFile.reindex_later("foo.md")
    end
  end

  test "Memory::IndexerJob is a thin wrapper for MemoryFile.reindex" do
    write_memory("from-job.md", "# From job\n")
    perform_enqueued_jobs do
      Memory::IndexerJob.perform_later("from-job.md")
    end
    assert MemoryFile.exists?(path: "from-job.md")
  end

  test "reindex! after a partial FTS failure can be repaired by replaying" do
    # Phase 2 hardening-gate item, updated for Phase 3 Task 3.16a M3:
    # SQLite cross-database transactions are best-effort and the FTS write
    # now lives in `after_commit` rather than inside the AR transaction.
    # If the FTS INSERT raises after the DELETE has gone through, the
    # primary-DB row is already committed (with the v2 digest) and the FTS
    # row is gone — a real-world partial failure. The self-healing path is
    # the `rescue ActiveRecord::StatementInvalid` in `flush_fts_write`,
    # which resets `content_digest` so the next `reindex!` re-runs.
    write_memory("repair.md", "# Repair\n")
    file = MemoryFile.reindex("repair.md")
    assert_equal 1, fts_count_for(file.id)

    write_memory("repair.md", "# Repair v2\n")
    fts_conn = MemoryFileFts.connection
    call_count = 0
    fts_conn.singleton_class.alias_method(:__real_execute, :execute)
    fts_conn.define_singleton_method(:execute) do |*args|
      call_count += 1
      raise ActiveRecord::StatementInvalid, "fts down" if call_count == 2
      __real_execute(*args)
    end
    begin
      assert_raises(ActiveRecord::StatementInvalid) { file.reindex! }
    ensure
      fts_conn.singleton_class.alias_method(:execute, :__real_execute)
      fts_conn.singleton_class.remove_method(:__real_execute)
    end

    # The primary-DB row is committed (v2 disk content was written) but the
    # digest was reset to "" by the rescue in `flush_fts_write`, marking the
    # row as needing re-indexing.
    assert_equal "", file.reload.content_digest

    # On a fresh sweep, `reindex!` notices the row's digest doesn't match
    # disk, re-runs, and restores the FTS row.
    file.reindex!
    assert_equal 1, fts_count_for(file.id)
    assert_equal Digest::SHA256.hexdigest("# Repair v2\n"), file.reload.content_digest
  end

  test "rollback of update! leaves no stale FTS row" do
    write_memory("safe.md", "# Safe\n")
    file = MemoryFile.reindex("safe.md")
    assert_equal 1, fts_count_for(file.id)

    write_memory("safe.md", "# Safe v2\n")
    file.define_singleton_method(:track_event) { |*_a, **_kw| raise "boom" }
    assert_raises(RuntimeError) { file.reindex! }
    # The FTS row is the v1 entry (unchanged) — after_commit never fired
    # because track_event rolled the transaction back.
    assert_equal 1, fts_count_for(file.id)
    fts_body = MemoryFileFts.connection.select_value(
      ActiveRecord::Base.sanitize_sql([
        "SELECT body FROM memory_files_fts WHERE memory_file_id = ?", file.id
      ])
    )
    assert_equal "# Safe\n", fts_body, "FTS body must still be v1, not v2"
  end

  private
    def write_memory(rel_path, body)
      absolute = File.join(@tmp, "memory", rel_path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, body)
    end

    def fts_count_for(memory_file_id)
      MemoryFileFts.connection.select_value(
        ActiveRecord::Base.sanitize_sql([
          "SELECT COUNT(*) FROM memory_files_fts WHERE memory_file_id = ?", memory_file_id
        ])
      )
    end

    def fts_rowid_for(memory_file_id)
      MemoryFileFts.connection.select_value(
        ActiveRecord::Base.sanitize_sql([
          "SELECT rowid FROM memory_files_fts WHERE memory_file_id = ?", memory_file_id
        ])
      )
    end
end
