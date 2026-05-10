class Columns::RunsController < ApplicationController
  before_action :require_project!
  before_action :set_column

  def index
    @runs = @column.runs.includes(:task).order(created_at: :desc).limit(100)
  end

  def show
    @run = @column.runs.find(params[:id])
  end

  private

  def set_column
    @column = Current.project.columns.find(params[:column_id])
  end
end
