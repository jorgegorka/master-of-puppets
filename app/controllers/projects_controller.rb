class ProjectsController < ApplicationController
  def index
    @projects = Current.user.projects.includes(:memberships)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    Project.transaction do
      @project.save!
      @project.memberships.create!(user: Current.user, role: :owner)
    end

    session[:project_id] = @project.id
    redirect_to root_path, notice: "#{@project.name} has been created."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit
    @project = Current.user.projects.find(params[:id])
  end

  def update
    @project = Current.user.projects.find(params[:id])

    if @project.update(project_params)
      redirect_to projects_path, notice: "Project settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :max_concurrent_agents)
  end
end
