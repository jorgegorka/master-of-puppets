module Tasks
  module CompletionTracking
    extend ActiveSupport::Concern

    included do
      after_commit :recalculate_parent_task_completion, on: %i[create update destroy]
      after_commit :sync_leaf_completion_percentage, on: :update
    end

    def recalculate_completion!
      total = subtasks.count
      done = subtasks.completed.count
      pct = total > 0 ? ((done.to_f / total) * 100).round : 0
      update_column(:completion_percentage, pct) unless completion_percentage == pct

      auto_advance_on_subtasks_completed! if pct == 100 && total > 0
    end

    private

    def auto_advance_on_subtasks_completed!
      return if column.nil? || column.terminal?

      next_column =
        if parent_task_id.present?
          project.columns.ordered.where("position > ?", column.position).find_by(kind: "review") ||
            project.columns.ordered.where("position > ?", column.position).first
        else
          project.columns.ordered.where("position > ?", column.position).find_by(kind: "done") ||
            project.columns.terminal.find_by(kind: "done")
        end

      return unless next_column

      enter_column!(next_column, actor: creator, kind: :advance, reason: "subtasks completed")
    end

    def recalculate_parent_task_completion
      return unless saved_change_to_column_id? || saved_change_to_parent_task_id? || previously_new_record? || destroyed?

      affected_id = parent_task_id || parent_task_id_before_last_save
      return unless affected_id

      RecalculateTaskCompletionJob.perform_later(affected_id)
    end

    def sync_leaf_completion_percentage
      return unless saved_change_to_column_id?
      return if subtasks.exists?

      new_pct = completed? ? 100 : 0
      update_column(:completion_percentage, new_pct) unless completion_percentage == new_pct
    end
  end
end
