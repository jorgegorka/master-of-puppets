module Skill::Loadable
  extend ActiveSupport::Concern

  class MalformedSkill < StandardError; end

  FRONTMATTER_RE = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

  included do
    after_destroy_commit :clear_fts_entry!
    after_commit :flush_fts_write, on: %i[create update]
  end

  class_methods do
    # Walks ${MOP_HOME}/skills/**/SKILL.md, upserts a row per file, and
    # tombstones rows whose source_path is gone. Returns the array of
    # source_paths that were seen.
    def reload_from_disk
      root = Pathname.new(Rails.application.config.x.mop_home).join("skills")
      seen = Pathname.glob(root.join("**/SKILL.md")).map(&:to_s)
      # `where.not(source_path: [])` collapses to `WHERE 1=1` in AR and would
      # destroy every Skill row — defend against a transient empty disk
      # (fresh install, missed seed copy, I/O blip) by skipping the tombstone
      # branch entirely when the walk found nothing.
      where.not(source_path: seen).destroy_all if seen.any?
      seen.each { |path| reload_path(path) }
      seen
    end

    # Load a single SKILL.md, tolerating a malformed file by logging a
    # warning rather than raising. Used by the watcher / boot-replay paths
    # so a single broken file doesn't blow up the whole reload pass.
    #
    # If the file is gone (the watcher fired `skills.changed` for a delete),
    # tombstone the row instead of raising — that's the only signal we get
    # back from the supervisor since it doesn't differentiate event kinds.
    def reload_path(path)
      unless File.exist?(path)
        find_by(source_path: path)&.destroy
        return
      end
      find_or_initialize_by(source_path: path).load_from_path!
    rescue MalformedSkill => e
      Rails.logger.warn("[Skill::Loadable] skipping #{path}: #{e.message}")
    end
  end

  def load_from_path!
    path = Pathname.new(source_path)
    manifest_yaml, body = parse_frontmatter!(path.read)
    digest = Digest::SHA256.hexdigest(body)

    return self if persisted? && digest == body_digest

    transaction do
      update!(
        slug:           manifest_yaml.fetch("name") { path.parent.basename.to_s },
        name:           manifest_yaml.fetch("name") { path.parent.basename.to_s },
        category:       manifest_yaml.fetch("category", path.parent.parent.basename.to_s),
        description:    manifest_yaml["description"],
        manifest:       manifest_yaml,
        source_path:    source_path,
        origin:         (origin || :builtin),
        security_level: derive_security_level(manifest_yaml, body),
        body_digest:    digest,
        discovered_at:  Time.current
      )
      @pending_fts_body = body
      track_event :reloaded, body_digest: digest
    end
    @body = body
    self
  end

  # after_commit hook (see `included do`). Runs the FTS write outside the
  # primary-DB transaction so a track_event rollback doesn't leave stale FTS
  # rows. Trade-off: if the FTS write itself fails, the AR row is committed
  # but FTS may be partial — reset body_digest so the next reindex pass
  # re-runs (self-healing).
  def flush_fts_write
    body = @pending_fts_body
    return unless body
    @pending_fts_body = nil
    reindex_fts_entry!(slug: slug, name: name, category: category,
                       description: description.to_s, body: body)
  rescue ActiveRecord::StatementInvalid
    update_columns(body_digest: "")
    raise
  end

  def body
    return @body if defined?(@body)
    @body = parse_frontmatter!(Pathname.new(source_path).read).last
  rescue Errno::ENOENT
    # The source file was deleted between reloads — render paths (Skill#show)
    # and FTS rebuilds must not 500. The next reload pass tombstones the row.
    @body = ""
  end

  private
    def derive_security_level(manifest, body)
      analysis = Skill::SecurityAnalysis.from(declared: manifest["security_level"] || "safe", body: body)
      Skill.security_levels[analysis.final_level.to_s]
    end

    def parse_frontmatter!(raw)
      match = raw.match(FRONTMATTER_RE)
      raise MalformedSkill, "no frontmatter at #{source_path}" unless match
      manifest_yaml = YAML.safe_load(match[1], permitted_classes: [ Symbol ])
      raise MalformedSkill, "frontmatter must be a Hash" unless manifest_yaml.is_a?(Hash)
      [ manifest_yaml.deep_stringify_keys, match[2] ]
    end
end
