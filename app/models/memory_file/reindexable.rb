module MemoryFile::Reindexable
  extend ActiveSupport::Concern

  included do
    after_destroy_commit :clear_fts_entry!
    after_commit :flush_fts_write, on: %i[create update]
  end

  class_methods do
    # Walks the memory root, refreshes a row for each `.md` file, and
    # tombstones rows whose disk file is gone. Returns the list of paths
    # that were seen.
    def reindex_all
      root = Pathname.new(Rails.application.config.x.mop_home).join("memory")
      seen = []
      Pathname.glob(root.join("**/*.md")).each do |file|
        rel = file.relative_path_from(root).to_s
        reindex(rel)
        seen << rel
      end
      # `where.not(path: [])` collapses to `WHERE 1=1` in AR — would destroy
      # every row on a transient empty walk. Cold-start callers (Phase 3
      # Memory::FullReindexJob) must not nuke the index because of a missed
      # mount or first-boot ordering glitch.
      where.not(path: seen).destroy_all if seen.any?
      seen
    end

    # Find-or-initialize by path, then call `#reindex!` on the result.
    def reindex(path)
      find_or_initialize_by(path: path).reindex!
    end
  end

  # Sync the disk file at `path` into the row + FTS index.
  #
  # Three branches:
  # - file gone & row persisted    → destroy
  # - file gone & row unpersisted  → no-op, return self
  # - file present                 → refresh row + FTS in a transaction
  #
  # Idempotent: re-running on an unchanged file short-circuits via the
  # `content_digest` guard so the FTS row doesn't churn.
  def reindex!
    wsp = workspace_path

    unless wsp.exist?
      destroy if persisted?
      return self
    end

    body          = wsp.read
    digest        = Digest::SHA256.hexdigest(body)
    return self if persisted? && digest == content_digest

    transaction do
      update!(
        title:          extract_title(body) || path,
        tags:           extract_tags(body),
        content_digest: digest,
        byte_size:      body.bytesize,
        disk_mtime:     File.mtime(wsp.absolute)
      )

      @pending_fts_body = body
      track_event :reindexed, byte_size: byte_size
    end
    self
  end

  # after_commit hook (see `included do`). Runs the FTS write outside the
  # primary-DB transaction so a track_event rollback doesn't leave stale FTS
  # rows. If the FTS write itself fails, reset content_digest so the next
  # reindex pass re-runs (self-healing).
  def flush_fts_write
    body = @pending_fts_body
    return unless body
    @pending_fts_body = nil
    reindex_fts_entry!(path: path, title: title.to_s, tags: Array(tags).join(" "), body: body)
  rescue ActiveRecord::StatementInvalid
    update_columns(content_digest: "")
    raise
  end

  private
    def extract_title(body)
      body.lines.first&.match(/\A#\s+(.+)$/)&.captures&.first&.strip
    end

    def extract_tags(body)
      body.scan(/(?:^|\s)#([\w\-]+)/).flatten.uniq.first(20)
    end
end
