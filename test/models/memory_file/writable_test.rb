require "test_helper"

class MemoryFile::WritableTest < ActiveSupport::TestCase
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

  test "write_at creates a row + disk file + FTS entry" do
    file = nil
    assert_difference -> { MemoryFile.count } => +1,
                      -> { Event.where(action: "memory_file_edited").count } => +1 do
      file = MemoryFile.write_at("note.md", "# Note\n\nhello")
    end

    assert_equal "# Note\n\nhello", File.read(File.join(@tmp, "memory/note.md"))
    assert_equal Digest::SHA256.hexdigest("# Note\n\nhello"), file.content_digest
    assert_equal "Note", file.title
    assert_equal 1, MemoryFileFts.connection.select_value(
      ActiveRecord::Base.sanitize_sql([
        "SELECT COUNT(*) FROM memory_files_fts WHERE memory_file_id = ?", file.id
      ])
    )
  end

  test "write creates intermediate directories" do
    MemoryFile.write_at("nested/sub/dir/page.md", "body")

    assert File.exist?(File.join(@tmp, "memory/nested/sub/dir/page.md"))
  end

  test "write is atomic: a failure mid-rename leaves the original file intact" do
    File.write(File.join(@tmp, "memory/safe.md"), "original")
    file = MemoryFile.reindex("safe.md")

    File.singleton_class.alias_method(:__real_rename, :rename)
    File.define_singleton_method(:rename) { |*| raise "disk failure" }
    begin
      assert_raises(RuntimeError) { file.write("would-be replacement") }
    ensure
      File.singleton_class.alias_method(:rename, :__real_rename)
      File.singleton_class.remove_method(:__real_rename)
    end

    assert_equal "original", File.read(File.join(@tmp, "memory/safe.md"))
    leftover_tmps = Dir.children(File.join(@tmp, "memory")).select { |f| f.include?(".tmp") }
    assert_empty leftover_tmps, "tmp file must be cleaned up on failure"
  end

  test "write self-heals the row update when the FTS sync fails" do
    # Updated for Phase 3 Task 3.16a M3: FTS writes moved out of the AR
    # transaction → after_commit. Under the new contract, the row update
    # commits before the FTS write fires; if the FTS write raises, the
    # `flush_fts_write` rescue resets content_digest so the next reindex
    # pass re-runs (self-healing). The disk/row consistency story moves
    # from "transactional rollback" to "digest mismatch on next pass".
    File.write(File.join(@tmp, "memory/db.md"), "before")
    file = MemoryFile.reindex("db.md")

    fts_connection = MemoryFileFts.connection
    fts_connection.singleton_class.alias_method(:__real_execute, :execute)
    fts_connection.define_singleton_method(:execute) do |*|
      raise ActiveRecord::StatementInvalid, "fts down"
    end
    begin
      assert_raises(ActiveRecord::StatementInvalid) { file.write("after") }
    ensure
      fts_connection.singleton_class.alias_method(:execute, :__real_execute)
      fts_connection.singleton_class.remove_method(:__real_execute)
    end

    # The digest is now "" — a sentinel that tells the next `reindex!` pass
    # that this row is out of sync with the FTS index and must be replayed.
    assert_equal "", file.reload.content_digest
  end
end
