class ColumnsController < ApplicationController
  before_action :require_project!
  before_action :set_column, only: %i[show edit update destroy]

  def index
    @columns = Current.project.columns.ordered.includes(:tasks)
  end

  def show
    @runs = @column.runs.includes(:task).order(created_at: :desc).limit(50)
  end

  def new
    @column = Current.project.columns.new(transition_policy: "manual")
  end

  def edit
  end

  def create
    @column = Current.project.columns.new(column_params)

    if @column.save
      redirect_to columns_path, notice: "Column created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @column.update(column_params)
      respond_to do |format|
        format.html { redirect_to columns_path, notice: "Column updated." }
        format.json { render json: { id: @column.id, position: @column.position } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @column.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @column.system_key.present?
      redirect_to columns_path, alert: "System columns cannot be destroyed."
      return
    end

    if @column.tasks.any?
      redirect_to columns_path, alert: "Cannot destroy a column with tasks. Move them first."
      return
    end

    @column.destroy
    redirect_to columns_path, notice: "Column destroyed."
  end

  private

  def set_column
    @column = Current.project.columns.find(params[:id])
  end

  def column_params
    params.require(:column).permit(
      :name, :description, :transition_policy, :position, :terminal,
      :kind, :hidden_by_default, :job_spec, :success_criteria,
      :adapter_type, :budget_cents, :max_concurrent_runs, :resumable_session,
      adapter_config: {}
    )
  end
end
