module McpServer::Enableable
  extend ActiveSupport::Concern

  included do
    # Discovery is dispatched after the row's transition to :unknown is
    # *committed*. If we enqueued inline inside `enable!`, a future caller
    # wrapping enable! in an outer transaction would let the job worker
    # (separate connection) read the pre-commit row and exit early. The
    # after_commit hook fires only on the outermost commit, so this stays
    # correct under nesting.
    after_commit :discover_tools_later, on: :update, if: :enabled_just_now?
  end

  def enable!
    return if reachable?
    transaction do
      update!(status: :unknown)
      track_event :enabled
    end
  end

  def disable!
    return if disabled?
    transaction do
      update!(status: :disabled)
      track_event :disabled
    end
  end

  private
    def enabled_just_now?
      saved_change_to_status? && status == "unknown"
    end
end
