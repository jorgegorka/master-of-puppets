class JobsChannel < ApplicationCable::Channel
  def subscribed
    scheduled_job = current_user.scheduled_jobs.find_by(id: params[:scheduled_job_id])
    if scheduled_job
      stream_for scheduled_job
    else
      Rails.logger.info("[JobsChannel] reject: user=#{current_user.id} scheduled_job_id=#{params[:scheduled_job_id]}")
      reject
    end
  end
end
