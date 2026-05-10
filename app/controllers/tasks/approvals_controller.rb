class Tasks::ApprovalsController < ApplicationController
  before_action :require_project!
  before_action :set_task

  def update
    unless @task.pending_review?
      redirect_to @task, alert: "Task is not pending review.", status: :see_other
      return
    end

    begin
      @task.approve_by!(Current.user)
      redirect_to tasks_path, notice: "Task approved."
    rescue Tasks::Reviewing::ReviewError => e
      redirect_to @task, alert: e.message, status: :see_other
    end
  end

  private

  def set_task
    @task = Current.project.tasks.find(params[:task_id])
  end
end
