class ScheduledJobs::CronPreviewsController < ApplicationController
  def show
    cron = ScheduledJob::Cron.new(params[:cron])
    render json: { next_run_at: cron.next_run_at.iso8601 }
  rescue ScheduledJob::Cron::Invalid, ScheduledJob::Cron::TooFrequent => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
