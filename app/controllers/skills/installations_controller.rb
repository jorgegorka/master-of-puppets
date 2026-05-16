class Skills::InstallationsController < ApplicationController
  before_action :set_skill

  def create
    @skill.install_for(Current.user)
    redirect_to @skill
  end

  def destroy
    @skill.uninstall_for(Current.user)
    redirect_to @skill
  end

  private
    def set_skill
      @skill = Skill.find(params[:skill_id])
    end
end
