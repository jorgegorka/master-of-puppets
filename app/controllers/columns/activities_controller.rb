class Columns::ActivitiesController < ApplicationController
  before_action :require_project!
  before_action :set_column

  def create
    return render_error("Manual columns do not run agents.") unless @column.agent?
    return render_error("Column is not yet configured.") unless @column.runnable?
    return render_error("No eligible tasks in this column.") if @column.terminal? || @column.tasks.empty?

    runs = @column.tasks.map { |t| @column.trigger_for(t, trigger_type: :manual, initiating_user: Current.user) }
    redirect_to columns_path, notice: "Started #{runs.compact.size} run(s)."
  end

  def destroy
    cancelled = @column.runs.active.find_each.count { |r| r.cancel! }
    redirect_to columns_path, notice: "Cancelled #{cancelled} active run(s)."
  end

  private

  def set_column
    @column = Current.project.columns.find(params[:column_id])
  end

  def render_error(msg)
    redirect_to columns_path, alert: msg, status: :see_other
  end
end
