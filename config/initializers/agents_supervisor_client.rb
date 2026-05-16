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

  AgentsSupervisor::Client.subscribe_to_memory_changes

  # Cold-start replay: any .md edits that happened while Puma or the
  # supervisor were down would otherwise sit unindexed forever (the
  # supervisor's listener only fires on events that arrive after a
  # client has connected). `reindex_all` is idempotent — `reindex!`
  # short-circuits unchanged files via digest match — so multi-worker
  # enqueues are safe.
  Memory::FullReindexJob.perform_later
  # Same story for skills: `Skill::ReloadJob.perform` with no path walks
  # the whole `${MOP_HOME}/skills/` tree. `load_from_path!` is idempotent
  # on unchanged content.
  Skill::ReloadJob.perform_later
end
