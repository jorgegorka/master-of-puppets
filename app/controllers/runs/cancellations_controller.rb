class Runs::CancellationsController < ApplicationController
  before_action :require_project!

  def create
    run = Current.project.runs.find(params[:run_id])
    if run.terminal?
      redirect_to run, alert: "Run already terminal.", status: :see_other
      return
    end

    run.cancel!
    redirect_to run, notice: "Run cancelled."
  end
end
