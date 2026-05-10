class Onboarding::AdaptersController < ApplicationController
  include Onboarding::Wizardable
  before_action :require_onboarding_project!

  def new
  end

  def create
    onboarding_project.cascade_adapter_config!(
      adapter_type: params[:adapter_type],
      adapter_config: adapter_config_params.to_h
    )

    redirect_to new_onboarding_completion_path
  end

  private

  def adapter_config_params
    params.fetch(:adapter_config, {}).permit!
  end
end
