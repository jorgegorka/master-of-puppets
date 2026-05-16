require "test_helper"

class MemoryFileSearchTest < ActiveSupport::TestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))

    # Phase 2 / Task 2.4: the FTS sync from `Reindexable` lands in Task 2.5;
    # we hand-insert FTS rows here so the search behaviour can be tested
    # independently of `reindex!`.
    @hello = create_indexed("hello.md",   "Hello world",      "hello world has lots to say")
    @world = create_indexed("world.md",   "World greetings",  "the world says hi and welcomes hello")
    @other = create_indexed("other.md",   "Unrelated note",   "nothing to see here, just notes")
  end

  teardown do
    MemoryFileFts.connection.execute("DELETE FROM memory_files_fts")
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "returns rows whose FTS body matches in bm25 order" do
    results = MemoryFile.matching("hello")

    refute_includes results, @other
    assert_includes results, @hello
    assert_includes results, @world

    # bm25 ranks the more focused match (@hello body mentions "hello" twice
    # in 5 tokens) above the looser one (@world mentions it once in 7).
    assert_equal @hello, results.first
  end

  test "blank query returns an empty array" do
    assert_equal [], MemoryFile.matching("")
    assert_equal [], MemoryFile.matching(nil)
  end

  test "no matches returns an empty array" do
    assert_equal [], MemoryFile.matching("nonexistentterm")
  end

  test "embedded quotes do not raise" do
    assert_nothing_raised { MemoryFile.matching('foo"bar') }
  end

  private
    def create_indexed(path, title, body)
      File.write(File.join(@tmp, "memory", path), body)
      file = MemoryFile.create!(
        path: path,
        title: title,
        content_digest: Digest::SHA256.hexdigest(body),
        byte_size: body.bytesize,
        disk_mtime: Time.current
      )
      MemoryFileFts.connection.execute(
        ActiveRecord::Base.sanitize_sql([
          "INSERT INTO memory_files_fts (memory_file_id, path, title, tags, body) VALUES (?, ?, ?, ?, ?)",
          file.id, file.path, file.title, "", body
        ])
      )
      file
    end
end
