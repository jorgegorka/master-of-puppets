class SkillsController < ApplicationController
  before_action :require_project!
  before_action :set_skill, only: [ :show, :edit, :update, :destroy ]

  def index
    @skills = Current.project.skills.includes(:columns).order(:name)
    @skills = @skills.by_category(params[:category]) if params[:category].present?
    @current_category = params[:category]
    @categories = Current.project.skills.where.not(category: [ nil, "" ]).distinct.pluck(:category).sort
  end

  def show
    @columns = @skill.columns.ordered
    @skill_document_links = @skill.skill_documents.joins(:document).includes(:document).order("documents.title")
  end

  def new
    @skill = Current.project.skills.new(builtin: false)
  end

  def create
    @skill = Current.project.skills.new(skill_params)
    @skill.builtin = false

    if @skill.save
      redirect_to @skill, notice: "#{@skill.name} skill has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @skill.update(skill_params)
      redirect_to @skill, notice: "#{@skill.name} skill has been updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @skill.builtin?
      redirect_to @skill, alert: "Built-in skills cannot be deleted."
      return
    end

    name = @skill.name
    @skill.destroy
    redirect_to skills_path, notice: "#{name} skill has been deleted."
  end

  private

  def set_skill
    @skill = Current.project.skills.find(params[:id])
  end

  def skill_params
    params.require(:skill).permit(:key, :name, :description, :markdown, :category)
  end
end
