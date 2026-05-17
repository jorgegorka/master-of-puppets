class AgentProfileSyncsController < ApplicationController
  before_action :require_admin

  def create
    AgentProfile.refresh_from_yaml!
    redirect_to agent_profiles_path
  end

  private
    def require_admin
      head :forbidden unless Current.user&.admin?
    end
end
