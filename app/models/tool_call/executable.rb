module ToolCall::Executable
  extend ActiveSupport::Concern

  def execute
    raise NotImplementedError, "tool execution lands in Phase 3"
  end
end
