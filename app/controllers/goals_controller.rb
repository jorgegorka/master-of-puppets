# Facade over root tasks (tasks with parent_task_id: nil). Kept as a
# separate controller + URL so the "Goals" nav label and /goals URL remain
# stable for users. Under the hood these are Task records.
class GoalsController < ApplicationController
  before_action :require_project!
  before_action :set_root_task, only: [ :show, :edit, :update, :destroy ]

  def index
    @root_tasks = Current.project.tasks.roots.by_priority
  end

  def show
    @detail = Task::Detail.new(@root_task)
  end

  def new
    @root_task = Current.project.tasks.new(creator: Current.user)
  end

  def create
    @root_task = Current.project.tasks.new(root_task_params.merge(creator: Current.user))

    if @root_task.save
      apply_recurrence_choice(@root_task)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("goals-list",
              partial: "dashboard/goal_card",
              locals: { goal: @root_task }),
            turbo_stream.remove("goals-empty")
          ]
        end
        format.html { redirect_to goal_path(@root_task), notice: "Goal '#{@root_task.title}' has been created." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @root_task.update(root_task_params)
      apply_recurrence_choice(@root_task)
      redirect_to goal_path(@root_task), notice: "Goal '#{@root_task.title}' has been updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @root_task.title
    @root_task.destroy
    redirect_to goals_path, notice: "Goal '#{title}' has been deleted."
  end

  private

  def set_root_task
    @root_task = Current.project.tasks.roots.find(params[:id])
  end

  def root_task_params
    params.require(:root_task).permit(:title, :description, :priority)
  end

  def apply_recurrence_choice(goal)
    if recurrence_requested?
      goal.make_recurrent(**recurrence_params, timezone: Current.user.timezone)
    elsif goal.recurring?
      goal.stop_recurring
    end
  end

  def recurrence_requested?
    ActiveModel::Type::Boolean.new.cast(params[:recurrent])
  end

  def recurrence_params
    params.require(:recurrence).permit(:interval, :unit, :anchor_date, :anchor_hour).to_h.symbolize_keys
  end
end
