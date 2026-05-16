class WorkspaceFile
  DEFAULT_IGNORE = %w[node_modules .git .next .turbo .cache __pycache__ .venv dist].freeze

  Node = Data.define(:name, :path, :directory, :children, :size_bytes, :mtime)

  def self.tree(root:, max_depth: 3, max_entries: 20_000, ignore: DEFAULT_IGNORE)
    base    = WorkspacePath.resolve(root: root, raw: ".").to_pathname
    counter = { count: 0 }
    walk(base, base, depth: 0, max_depth: max_depth, max_entries: max_entries, ignore: ignore, counter: counter)
  end

  def self.walk(base, dir, depth:, max_depth:, max_entries:, ignore:, counter:)
    return [] if depth > max_depth
    entries = []
    dir.each_child do |child|
      break if counter[:count] >= max_entries
      next if ignore.include?(child.basename.to_s)
      next if child.symlink? && !safe_symlink?(base, child)
      counter[:count] += 1
      rel = child.relative_path_from(base).to_s
      if child.directory?
        children = walk(base, child, depth: depth + 1, max_depth: max_depth, max_entries: max_entries, ignore: ignore, counter: counter)
        entries << Node.new(child.basename.to_s, rel, true, children, nil, child.mtime)
      else
        entries << Node.new(child.basename.to_s, rel, false, [], child.size, child.mtime)
      end
    end
    entries.sort_by { |n| [ n.directory ? 0 : 1, n.name.downcase ] }
  end

  # Skip symlinks whose target lands outside `base`. We don't need to follow
  # them for the tree view, and resolving them risks both stack overflow on
  # cycles and the same path-escape we guard against in `WorkspacePath`.
  def self.safe_symlink?(base, path)
    real = path.realpath
    real.to_s == base.to_s || real.to_s.start_with?(base.to_s + File::SEPARATOR)
  rescue Errno::ENOENT, Errno::ELOOP
    false
  end
end
