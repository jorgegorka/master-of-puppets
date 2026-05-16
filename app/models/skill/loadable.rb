module Skill::Loadable
  extend ActiveSupport::Concern

  class MalformedSkill < StandardError; end

  FRONTMATTER_RE = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

  class_methods do
    # Walks ${MOP_HOME}/skills/**/SKILL.md, upserts a row per file, and
    # tombstones rows whose source_path is gone. Returns the array of
    # source_paths that were seen.
    def reload_from_disk
      root = Pathname.new(Rails.application.config.x.mop_home).join("skills")
      seen = Pathname.glob(root.join("**/SKILL.md")).map(&:to_s)
      where.not(source_path: seen).destroy_all
      seen.each do |path|
        skill = find_or_initialize_by(source_path: path)
        skill.load_from_path!
      end
      seen
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
      track_event :reloaded, body_digest: digest
    end
    @body = body
    self
  end

  def body
    return @body if defined?(@body)
    @body = parse_frontmatter!(Pathname.new(source_path).read).last
  end

  private
    # Phase 3 Task 3.3 replaces this with Skill::SecurityAnalyzable. For now
    # honour the frontmatter declaration with `safe` as the default.
    def derive_security_level(manifest, _body)
      Skill.security_levels.fetch(manifest["security_level"].to_s, 0)
    end

    def parse_frontmatter!(raw)
      match = raw.match(FRONTMATTER_RE)
      raise MalformedSkill, "no frontmatter at #{source_path}" unless match
      manifest_yaml = YAML.safe_load(match[1], permitted_classes: [ Symbol ])
      raise MalformedSkill, "frontmatter must be a Hash" unless manifest_yaml.is_a?(Hash)
      [ manifest_yaml.deep_stringify_keys, match[2] ]
    end
end
