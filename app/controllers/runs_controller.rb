class RunsController < ApplicationController
  before_action :require_project!

  def show
    @run = Current.project.runs.find(params[:id])
  end
end
