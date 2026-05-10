class Tasks::TransitionsController < ApplicationController
  before_action :require_project!
  before_action :set_task

  def create
    target = Current.project.columns.find(params[:target_column_id])

    transition = Columns::Transition.new(
      task: @task,
      actor: Current.user,
      kind: :manual_move,
      reason: params[:reason],
      target_column: target
    )

    unless transition.valid?
      redirect_to @task, alert: transition.errors.full_messages.to_sentence, status: :see_other
      return
    end

    @task.enter_column!(transition.target_column, actor: Current.user, kind: :manual_move, reason: params[:reason])

    respond_to do |format|
      format.html { redirect_to tasks_path, notice: "Task moved to #{target.name}." }
      format.json { render json: { id: @task.id, column_id: target.id } }
      format.turbo_stream
    end
  end

  private

  def set_task
    @task = Current.project.tasks.find(params[:task_id])
  end
end
