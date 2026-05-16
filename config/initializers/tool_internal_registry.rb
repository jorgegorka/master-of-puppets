Rails.application.config.after_initialize do
  classes = [
    "Tool::Internal::ReadFile",
    "Tool::Internal::WriteFile",
    "Tool::Internal::ListDir",
    "Tool::Internal::RunShell"
  ].filter_map { |name| name.safe_constantize }
  classes.each { |klass| Tool::Internal.register(klass.tool_name, klass) }
end
