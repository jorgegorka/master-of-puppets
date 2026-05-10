class TasksController < ApplicationController
  KANBAN_COLUMN_LIMIT = 100

  before_action :require_project!
  before_action :set_task, only: %i[show edit update destroy]

  def index
    @show_cancelled = boolean_param(:show_cancelled)
    @show_blocked   = boolean_param(:show_blocked)
    @overdue_filter = boolean_param(:overdue)
    @parent_filter  = Current.project.tasks.find_by(id: params[:parent_task_id]) if params[:parent_task_id].present?

    hidden_kinds = []
    hidden_kinds << "cancelled" unless @show_cancelled
    hidden_kinds << "blocked" unless @show_blocked

    @columns = Current.project.columns.ordered.where.not(kind: hidden_kinds.empty? ? [ nil ] : hidden_kinds)
    @columns = @columns.where("hidden_by_default = ? OR kind IN (?)", false, hidden_kinds) if hidden_kinds.empty?
    @counts_by_column = filtered_scope.group(:column_id).count

    @tasks_by_column = @columns.index_with do |column|
      base_scope.where(column_id: column.id).limit(KANBAN_COLUMN_LIMIT).to_a
    end
    @kanban_column_limit = KANBAN_COLUMN_LIMIT
  end

  def show
    @detail = Task::Detail.new(@task)
  end

  def new
    @task = Current.project.tasks.new(parent_task_id: params[:parent_task_id])
  end

  def create
    @task = Current.project.tasks.new(task_params.merge(creator: Current.user))

    if @task.save
      redirect_to @task, notice: "Task '#{@task.title}' has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      redirect_to @task, notice: "Task '#{@task.title}' has been updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy
    redirect_to tasks_path, notice: "Task '#{@task.title}' has been deleted."
  end

  private

  def set_task
    @task = Current.project.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :description, :priority, :due_at, :parent_task_id, :column_id)
  end

  def filtered_scope
    scope = Current.project.tasks
    scope = scope.where(parent_task_id: @parent_filter) if @parent_filter
    scope = scope.overdue if @overdue_filter
    scope
  end

  def base_scope
    filtered_scope
      .left_joins(:messages)
      .includes(:column, :creator, :parent_task)
      .select("tasks.*, COUNT(messages.id) AS messages_count")
      .group("tasks.id")
      .by_priority
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end
end
