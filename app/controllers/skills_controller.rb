class SkillsController < ApplicationController
  before_action :require_admin, only: %i[update destroy]
  before_action :set_skill, only: %i[show update destroy]

  def index
    @query  = params[:q].to_s
    @skills = @query.present? ? Skill.matching(@query) : Skill.all.order(:category, :name)
    @categories = Skill.distinct.pluck(:category).sort
  end

  def show
    @installed = @skill.installed_for?(Current.user)
    @enabled   = @skill.enabled_for?(Current.user)
  end

  def update
    @skill.load_from_path!
    redirect_to @skill, notice: "Reloaded from disk."
  end

  def destroy
    @skill.destroy
    redirect_to skills_path, notice: "Removed."
  end

  private
    def set_skill
      @skill = Skill.find(params[:id])
    end
end
