Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if defined?(Rails::Console)
  next if defined?(Rails::Generators)
  next if defined?(Rake) && Rake.application&.top_level_tasks&.any?
  next unless Rails.application.config.x.mop_home

  AgentsSupervisor::Client.subscribe_to_memory_changes

  # Cold-start replay: any .md edits that happened while Puma or the
  # supervisor were down would otherwise sit unindexed forever (the
  # supervisor's listener only fires on events that arrive after a
  # client has connected). `reindex_all` is idempotent — `reindex!`
  # short-circuits unchanged files via digest match — so multi-worker
  # enqueues are safe.
  Memory::FullReindexJob.perform_later
end
