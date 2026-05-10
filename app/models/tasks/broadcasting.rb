module Tasks
  module Broadcasting
    extend ActiveSupport::Concern

    included do
      after_commit :broadcast_goal_card_update, on: %i[create update],
        if: -> { saved_change_to_column_id? || saved_change_to_title? }
      after_commit :broadcast_attention_section, on: %i[create update],
        if: :attention_relevant_change?
    end

    private

    def attention_relevant_change?
      saved_change_to_column_id?
    end

    def broadcast_goal_card_update
      return unless project_id

      goal = root_ancestor
      goal = Task.includes(:column, :subtasks).find(goal.id) if goal.id != id
      Turbo::StreamsChannel.broadcast_replace_to(
        "dashboard_project_#{project_id}",
        target: "goal_card_task_#{goal.id}",
        partial: "dashboard/goal_card",
        locals: { goal: goal }
      )
    rescue ActionView::Template::Error, ActiveRecord::StatementInvalid => e
      Rails.logger.warn("[Task##{id}] goal card broadcast failed: #{e.message}")
    end

    def broadcast_attention_section
      return unless project_id

      Dashboard::AttentionItems.new(project).broadcast_to(project_id)
    rescue ActionView::Template::Error, ActiveRecord::StatementInvalid, NameError => e
      Rails.logger.warn("[Task##{id}] attention section broadcast failed: #{e.message}")
    end
  end
end
