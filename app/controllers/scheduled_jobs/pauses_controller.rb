class ScheduledJobs::PausesController < ApplicationController
  include ScheduledJobScoped

  def create
    @scheduled_job.pause(reason: params[:reason])
    redirect_to @scheduled_job, notice: "Paused."
  end

  def destroy
    @scheduled_job.resume
    redirect_to @scheduled_job, notice: "Resumed."
  end
end
