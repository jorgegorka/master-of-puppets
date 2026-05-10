class Tasks::RejectionsController < ApplicationController
  before_action :require_project!
  before_action :set_task

  def update
    unless @task.pending_review?
      redirect_to @task, alert: "Task is not pending review.", status: :see_other
      return
    end

    begin
      @task.reject_by!(Current.user, feedback: params[:feedback].to_s)
      redirect_to tasks_path, notice: "Task rejected."
    rescue Tasks::Reviewing::ReviewError => e
      redirect_to @task, alert: e.message, status: :see_other
    end
  end

  private

  def set_task
    @task = Current.project.tasks.find(params[:task_id])
  end
end
