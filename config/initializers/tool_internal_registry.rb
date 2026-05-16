Rails.application.config.after_initialize do
  # `run_shell` is default-off in production. Full sandboxing (rlimits + uid
  # drop + namespaces) lands with the Phase 4 supervisor v2; until then the
  # only safety nets are the admin-only invoke check and the audit log.
  run_shell_default = Rails.env.production? ? "false" : "true"
  run_shell_enabled = ENV.fetch("MOP_ENABLE_RUN_SHELL", run_shell_default) == "true"

  names = %w[Tool::Internal::ReadFile Tool::Internal::WriteFile Tool::Internal::ListDir]
  names << "Tool::Internal::RunShell" if run_shell_enabled

  names.filter_map(&:safe_constantize).each do |klass|
    Tool::Internal.register(klass.tool_name, klass)
  end
end
