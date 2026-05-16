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
