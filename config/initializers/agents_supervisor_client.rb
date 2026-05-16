Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if defined?(Rails::Console)
  next if defined?(Rails::Generators)
  next unless Rails.application.config.x.mop_home

  AgentsSupervisor::Client.subscribe_to_memory_changes
end
