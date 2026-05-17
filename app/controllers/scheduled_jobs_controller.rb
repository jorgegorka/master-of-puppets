class ScheduledJobsController < ApplicationController
  include ScheduledJobScoped
  skip_before_action :set_scheduled_job, only: %i[index new create]

  def index
    @scheduled_jobs = Current.user.scheduled_jobs.includes(:pause_record).order(:name)
  end

  def show
    @recent_runs = @scheduled_job.runs.recent.limit(20)
  end

  def new
    @scheduled_job = Current.user.scheduled_jobs.new(model: default_model, provider: "anthropic")
  end

  def create
    @scheduled_job = Current.user.scheduled_jobs.new(scheduled_job_params)
    if @scheduled_job.save
      redirect_to @scheduled_job, notice: "Job scheduled."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @scheduled_job.update(scheduled_job_params)
      redirect_to @scheduled_job, notice: "Job updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @scheduled_job.destroy
    redirect_to scheduled_jobs_path, notice: "Job removed."
  end

  private
    def scheduled_job_params
      params.expect(scheduled_job: [ :name, :cron, :prompt, :model, :provider, { skill_slugs: [] } ])
    end

    def default_model
      ENV.fetch("MOP_DEFAULT_MODEL") { Llm::Pricing.models_for("anthropic").first }
    end
end
