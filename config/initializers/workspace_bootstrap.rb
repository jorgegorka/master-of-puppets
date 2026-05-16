module WorkspaceBootstrap
  SUBDIRS = %w[memory skills profiles artifacts logs].freeze
  SEED_MEMORY = "# Memory\n\nIndex of memory notes.\n"

  def self.run(root)
    pathname = Pathname.new(root)
    SUBDIRS.each { |sub| FileUtils.mkdir_p(pathname.join(sub)) }

    memory_md = pathname.join("memory/MEMORY.md")
    File.write(memory_md, SEED_MEMORY) unless memory_md.exist?

    copy_seed_skills(pathname.join("skills"))
  end

  # Copy seed skills into the workspace on first boot. Never clobber edited
  # skills on disk — the disk is source of truth once a skill is in place.
  def self.copy_seed_skills(skills_root)
    seed_dir = Rails.root.join("db/seeds/skills")
    return unless seed_dir.directory?

    Dir.glob(seed_dir.join("**/SKILL.md")).each do |seed|
      rel  = Pathname.new(seed).relative_path_from(seed_dir)
      dest = skills_root.join(rel)
      next if dest.exist?  # idempotent — already on disk
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.cp(seed, dest)
    end
  end
end

Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if defined?(Rails::Console)
  next if defined?(Rails::Generators)
  # `Rake.application` is autoloaded but raises NoMethodError when not set
  # (e.g. `bin/rails routes` triggers Rake's autoload without calling
  # `Rake.application=`). Guard with `respond_to?` so non-rake commands
  # don't blow up here.
  next if defined?(Rake) && Rake.respond_to?(:application) && Rake.application&.top_level_tasks&.any?
  next unless Rails.application.config.x.mop_home

  # WorkspaceBootstrap.run is idempotent (mkdir_p + non-clobbering seed copy),
  # so every worker still runs it cheaply — no fan-out cost.
  WorkspaceBootstrap.run(Rails.application.config.x.mop_home)

  # Replay any skill edits that happened while Puma was down. Idempotent
  # because Skill::Loadable short-circuits on unchanged body_digest, and
  # Skill::ReloadJob's concurrency control collapses duplicate enqueues
  # across Puma workers. Still, gate to worker 0 to avoid waking N replicas.
  next unless ActiveRecord::Base.connection.data_source_exists?("skills")
  next unless BootReplayLeader.leader?
  Skill::ReloadJob.perform_later
end
