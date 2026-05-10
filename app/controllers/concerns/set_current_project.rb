module SetCurrentProject
  extend ActiveSupport::Concern

  included do
    before_action :set_current_project
    helper_method :current_project
  end

  private

  def current_project
    Current.project
  end

  def set_current_project
    return unless Current.user

    if session[:project_id]
      Current.project = Current.user.projects.find_by(id: session[:project_id])
    end

    # If session project is invalid (user removed from it), clear it
    if session[:project_id] && Current.project.nil?
      session.delete(:project_id)
    end

    # If user has projects but none selected, auto-select first
    if Current.project.nil? && Current.user.projects.any?
      Current.project = Current.user.projects.first
      session[:project_id] = Current.project.id
    end
  end

  def require_project!
    redirect_to new_onboarding_project_path unless Current.project
  end
end
