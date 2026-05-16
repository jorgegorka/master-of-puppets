class Skills::EnablementsController < ApplicationController
  before_action :set_skill
  rescue_from Skill::Enableable::NotInstalled, with: :require_install

  def create
    @skill.enable_for(Current.user)
    redirect_to @skill
  end

  def destroy
    @skill.disable_for(Current.user)
    redirect_to @skill
  end

  private
    def set_skill
      @skill = Skill.find(params[:skill_id])
    end

    def require_install(error)
      redirect_to @skill, alert: error.message
    end
end
