class Tasks::BulkUpdatesController < ApplicationController
  before_action :require_project!
  before_action :load_tasks

  ALLOWED_ATTRIBUTES = %w[column_id priority].freeze

  def create
    attribute = bulk_params[:attribute]
    value     = bulk_params[:value]

    return head :unprocessable_entity unless ALLOWED_ATTRIBUTES.include?(attribute)

    target_column = attribute == "column_id" ? Current.project.columns.find_by(id: value) : nil
    return head :unprocessable_entity if attribute == "column_id" && target_column.nil?

    updated = @tasks.select { |task| apply_bulk_change(task, attribute, value, target_column: target_column) }

    redirect_to tasks_path(redirect_filters), notice: "#{updated.size} task(s) updated."
  end

  def destroy
    destroyed = @tasks.select(&:destroy)
    redirect_to tasks_path(redirect_filters), notice: "#{destroyed.size} task(s) deleted."
  end

  private

  def apply_bulk_change(task, attribute, value, target_column: nil)
    if attribute == "column_id"
      Columns::Transition.new(task: task, actor: Current.user, kind: :manual_move, target_column: target_column).call
    else
      old = task.public_send(attribute)
      return false unless task.update(attribute => value)
      task.record_audit_event!(actor: Current.user, action: "#{attribute}_changed", metadata: { from: old, to: value })
      true
    end
  end

  def load_tasks
    ids = Array.wrap(params[:ids]).flat_map { |v| v.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    @tasks = Current.project.tasks.where(id: ids).to_a
    head :unprocessable_entity if @tasks.empty?
  end

  def bulk_params
    params.permit(:attribute, :value)
  end

  def redirect_filters
    params.slice(:parent_task_id, :overdue, :show_cancelled, :show_blocked).to_unsafe_h
  end
end
