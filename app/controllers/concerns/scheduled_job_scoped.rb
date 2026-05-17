module ScheduledJobScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_scheduled_job
  end

  private
    def set_scheduled_job
      @scheduled_job = Current.user.scheduled_jobs.find(params[:scheduled_job_id] || params[:id])
    end
end
