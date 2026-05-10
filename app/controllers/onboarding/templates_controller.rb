class Onboarding::TemplatesController < ApplicationController
  include Onboarding::Wizardable
  before_action :require_onboarding_project!

  # Templates as such are gone with the role-centric model.
  # The step persists as a no-op pass-through until column templates ship.
  def new
    @templates = []
  end

  def create
    redirect_to new_onboarding_adapter_path
  end
end
