class WorkspacePath
  class EscapeAttempt < StandardError; end

  # The set of workspace roots that callers are allowed to address. "." is
  # the whole workspace (used by Files::NodesController); the rest mirror
  # `WorkspaceBootstrap::SUBDIRS`. Keeping this explicit means a future
  # caller passing user-controlled input as `root:` can't escape into
  # arbitrary parent directories.
  ALLOWED_ROOTS = (WorkspaceBootstrap::SUBDIRS + [ "." ]).freeze

  attr_reader :absolute, :rel, :root_key

  def self.resolve(root:, raw:)
    new(root: root, raw: raw)
  end

  def initialize(root:, raw:)
    root_string = root.to_s
    unless ALLOWED_ROOTS.include?(root_string)
      raise EscapeAttempt, "unknown root #{root_string.inspect}"
    end

    raw_string = raw.to_s
    raise EscapeAttempt, "null byte"        if raw_string.include?("\0")
    raise EscapeAttempt, "backslash"        if raw_string.include?("\\")
    raise EscapeAttempt, "absolute path"    if Pathname.new(raw_string).absolute?

    @root_key = root
    base = Pathname.new(File.join(Rails.application.config.x.mop_home, root_string)).realpath

    # Textual check first — defeats `../../../etc/passwd` and friends without
    # ever touching disk, so we don't crash on realpath of a non-existent
    # parent that landed outside the workspace.
    cleaned = base.join(raw_string).cleanpath
    unless cleaned.to_s == base.to_s || cleaned.to_s.start_with?(base.to_s + File::SEPARATOR)
      raise EscapeAttempt, "#{raw_string.inspect} escapes #{root}"
    end

    @absolute =
      if cleaned.exist?
        cleaned.realpath
      else
        # The path doesn't exist yet (e.g. a new file we're about to write,
        # possibly under a directory tree that hasn't been mkdir'd). Walk
        # up to the closest existing ancestor, realpath that (to resolve
        # any symlinks), then rejoin the still-virtual tail.
        ancestor = cleaned
        ancestor = ancestor.parent until ancestor.exist?
        ancestor.realpath.join(cleaned.relative_path_from(ancestor))
      end

    # Second check after realpath catches symlinks that point outside the
    # root — cleanpath alone can't see those.
    unless @absolute.to_s == base.to_s || @absolute.to_s.start_with?(base.to_s + File::SEPARATOR)
      raise EscapeAttempt, "#{raw_string.inspect} escapes #{root}"
    end

    @rel = @absolute.relative_path_from(base).to_s
  end

  def to_s        = absolute.to_s
  def to_pathname = absolute
  def read        = File.read(absolute)
  def exist?      = absolute.exist?
end
