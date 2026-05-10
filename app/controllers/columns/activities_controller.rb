class Columns::ActivitiesController < ApplicationController
  before_action :require_project!
  before_action :set_column

  def create
    return render_error("Manual columns do not run agents.") unless @column.agent?
    return render_error("Column is not yet configured.") unless @column.runnable?

    eligible_tasks = @column.tasks.select { |t| !t.column.terminal? }
    return render_error("No eligible tasks in this column.") if eligible_tasks.empty?

    runs = eligible_tasks.map { |t| @column.trigger_for(t, trigger_type: :manual, initiating_user: Current.user) }
    redirect_to columns_path, notice: "Started #{runs.compact.size} run(s)."
  end

  def destroy
    cancelled = 0
    @column.runs.active.find_each do |r|
      begin
        r.cancel!
        cancelled += 1
      rescue StandardError
        # ignore
      end
    end
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
