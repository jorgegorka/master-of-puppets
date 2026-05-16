class SkillsController < ApplicationController
  before_action :require_admin, only: %i[update]
  before_action :set_skill, only: %i[show update]

  def index
    @query  = params[:q].to_s
    @skills = @query.present? ? Skill.matching(@query) : Skill.all.order(:category, :name)
  end

  def show
    @installed = @skill.installed_for?(Current.user)
    @enabled   = @skill.enabled_for?(Current.user)
  end

  def update
    Skill::ReloadJob.perform_later(path: @skill.source_path)
    redirect_to @skill, notice: "Reload queued."
  end

  private
    def set_skill
      @skill = Skill.find(params[:id])
    end
end
