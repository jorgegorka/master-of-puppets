module Tasks
  module ColumnFlow
    extend ActiveSupport::Concern

    AUDIT_ACTIONS = {
      "advance" => "task_advanced",
      "reject" => "task_rejected",
      "block" => "task_blocked",
      "manual_move" => "task_manual_moved",
      "cancel" => "task_cancelled"
    }.freeze

    # Single owner of column-membership side effects.
    # Mutation, audit, broadcast, job enqueue, all in one transaction.
    def enter_column!(target_column, actor:, kind:, reason: nil, feedback: nil)
      raise ArgumentError, "kind must be one of #{Columns::Transition::KINDS.join(', ')}" unless Columns::Transition::KINDS.include?(kind.to_s)
      raise ArgumentError, "target_column required" unless target_column

      from_column = column
      ApplicationRecord.transaction do
        attrs = {
          column: target_column,
          entered_column_at: Time.current,
          position: next_position_in(target_column)
        }
        attrs[:reviewer_feedback] = feedback if feedback.present?

        if kind.to_s == "advance" && from_column&.kind == "review" && actor.is_a?(User)
          attrs[:reviewed_at] = Time.current
          attrs[:reviewed_by_user_id] = actor.id
        end

        if target_column.terminal?
          attrs[:completed_at] ||= Time.current
        elsif from_column&.terminal?
          attrs[:completed_at] = nil
        end

        update!(attrs)

        record_audit_event!(
          actor: audit_actor_for(actor),
          action: AUDIT_ACTIONS.fetch(kind.to_s),
          metadata: {
            from_column_id: from_column&.id,
            from_column_name: from_column&.name,
            to_column_id: target_column.id,
            to_column_name: target_column.name,
            reason: reason,
            feedback: feedback
          }.compact
        )
      end

      TriggerColumnJob.perform_later(id) if target_column.agent? && !target_column.terminal?
      broadcast_board_movement(from_column: from_column, to_column: target_column)
      self
    end

    def cancel!(actor:, reason: nil)
      target = project.columns.find_by(system_key: "cancelled")
      raise "Project has no cancelled column" unless target
      enter_column!(target, actor: actor, kind: :cancel, reason: reason)
    end

    def previous_column
      audit_events
        .where(action: AUDIT_ACTIONS.values)
        .order(created_at: :desc)
        .pluck(Arel.sql("json_extract(metadata, '$.from_column_id')"))
        .compact
        .first
        &.then { |id| project.columns.find_by(id: id) }
    end

    private

    def next_position_in(target_column)
      (target_column.tasks.maximum(:position) || 0) + 1
    end

    def audit_actor_for(actor)
      case actor
      when Run then actor.column
      when User, Column then actor
      else actor
      end
    end

    def broadcast_board_movement(from_column:, to_column:)
      stream = "project_#{project_id}_board"
      [ from_column, to_column ].compact.uniq.each do |col|
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "kanban-column-#{col.id}",
          partial: "tasks/column",
          locals: { column: col, tasks: col.tasks.reload.to_a }
        )
      end
    rescue ActionView::Template::Error => e
      Rails.logger.warn("[Task##{id}] board movement broadcast failed: #{e.message}")
    end
  end
end
