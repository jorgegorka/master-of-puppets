class Onboarding::CompletionsController < ApplicationController
  include Onboarding::Wizardable
  before_action :require_onboarding_project!

  def new
    @project = onboarding_project
    @columns = @project.columns.ordered
  end

  def create
    session.delete(:onboarding)
    redirect_to columns_path, notice: "Your project is ready!"
  end
end
