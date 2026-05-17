class ScheduledJobs::RunsController < ApplicationController
  include ScheduledJobScoped

  before_action :set_run, only: :show

  def index
    @runs = @scheduled_job.runs.recent.limit(50)
  end

  def show
  end

  def create
    @scheduled_job.run_later
    redirect_to @scheduled_job, notice: "Run queued."
  end

  private
    def set_run
      @run = @scheduled_job.runs.find(params[:id])
    end
end
