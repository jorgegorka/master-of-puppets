module MemoryFile::Writable
  extend ActiveSupport::Concern

  class_methods do
    # Public entry point for "write content to <path>, creating the row if
    # needed". Lets callers (controllers, jobs, the supervisor) treat write
    # as the primitive without first hydrating a `MemoryFile`.
    def write_at(path, content)
      file = find_or_initialize_by(path: path)
      unless file.persisted?
        file.assign_attributes(
          content_digest: "pending",
          byte_size:      0,
          disk_mtime:     Time.current
        )
        file.save!(validate: false)
      end
      file.write(content)
    end
  end

  # Atomically writes `content` to the workspace file, reindexes
  # synchronously, and tracks an `:edited` event.
  #
  # The tmp → fsync → rename dance keeps the watcher (Task 2.11) from
  # seeing a partial file. After the rename, `reindex!` recomputes the
  # digest from disk; if the watcher fires too, its job will short-circuit
  # because the digest will match (Reindexable idempotency).
  def write(content)
    transaction do
      wsp = WorkspacePath.resolve(root: "memory", raw: path)
      FileUtils.mkdir_p(wsp.absolute.dirname)

      tmp = wsp.absolute.dirname.join(".#{wsp.absolute.basename}.#{SecureRandom.hex(4)}.tmp")
      begin
        File.open(tmp, "w") do |f|
          f.write(content)
          f.fsync
        end
        File.rename(tmp, wsp.absolute)
      rescue
        FileUtils.rm_f(tmp)
        raise
      end

      reindex!
      track_event :edited, byte_size: byte_size
    end
    self
  end
end
