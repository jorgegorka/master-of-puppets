class Tasks::BulkUpdatesController < ApplicationController
  before_action :require_project!
  before_action :load_tasks

  ALLOWED_ATTRIBUTES = %w[ status assignee_id priority ].freeze

  def create
    attribute = bulk_params[:attribute]
    value     = bulk_params[:value]

    return head :unprocessable_entity unless ALLOWED_ATTRIBUTES.include?(attribute)

    updated = @tasks.select { |task| apply_bulk_change(task, attribute, value) }

    redirect_to tasks_path(redirect_filters), notice: "#{updated.size} task(s) updated."
  end

  def destroy
    destroyed = @tasks.select(&:destroy)
    redirect_to tasks_path(redirect_filters), notice: "#{destroyed.size} task(s) deleted."
  end

  private

  def apply_bulk_change(task, attribute, value)
    old = task.public_send(attribute)
    return false unless task.update(attribute => value)

    task.record_audit_event!(
      actor: Current.user,
      action: audit_action_for(attribute),
      metadata: audit_metadata_for(task, attribute, old, value)
    )
    true
  end

  def audit_action_for(attribute)
    attribute == "assignee_id" ? "assigned" : "#{attribute}_changed"
  end

  def audit_metadata_for(task, attribute, old, value)
    if attribute == "assignee_id"
      { assignee_id: value, assignee_name: task.assignee&.title }
    else
      { from: old, to: value }
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
    params.slice(:assignee_id, :parent_task_id, :overdue, :show_cancelled).to_unsafe_h
  end
end
