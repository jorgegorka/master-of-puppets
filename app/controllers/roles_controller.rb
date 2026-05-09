class RolesController < ApplicationController
  before_action :require_project!
  before_action :set_role, only: [ :show, :edit, :update, :destroy ]

  def index
    respond_to do |format|
      format.html do
        @roles = Current.project.roles.includes(:parent, :children, :skills, :role_category).order(:title)
        @view = params[:view] || "chart"

        if @view == "chart"
          @roles_by_parent_id = @roles.group_by(&:parent_id)
          @root_roles = @roles_by_parent_id[nil] || []
        end
      end

      format.json { render json: search_active_roles }
    end
  end

  def show
    @detail = Role::Detail.new(@role, Current.project)
  end

  def new
    @role = Current.project.roles.new(new_role_defaults)
    @role_categories = Current.project.role_categories.order(:name)
    @library_roles = RoleLibrary::Registry.all
    @library_key = params[:library_key].presence
    apply_library_prefill(@role, @library_key) if @library_key
    @reparent_child_id = reparent_child_id
  end

  def create
    @role = Current.project.roles.new(role_params)
    library_key = params[:library_key].presence

    if reparent_child_id.present?
      child = Current.project.roles.find(reparent_child_id)
      @role.insert_above(child)
    else
      @role.save!
    end

    assign_library_skills(@role, library_key) if library_key
    redirect_to @role, notice: "#{@role.title} has been created."
  rescue ActiveRecord::RecordInvalid
    @role_categories = Current.project.role_categories.order(:name)
    @library_roles = RoleLibrary::Registry.all
    @library_key = params[:library_key].presence
    @reparent_child_id = reparent_child_id
    render :new, status: :unprocessable_entity
  end

  def edit
    @role_categories = Current.project.role_categories.order(:name)
  end

  def update
    if @role.update(role_params)
      sync_approval_gates
      redirect_to @role, notice: "#{@role.title} has been updated."
    else
      @role_categories = Current.project.role_categories.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @role.destroy
    redirect_to roles_path, notice: "#{@role.title} has been deleted."
  end

  private

  def search_active_roles
    scope = Current.project.roles.active.order(:title)
    query = params[:q].to_s.strip
    if query.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(query)
      scope = scope.where("LOWER(title) LIKE ?", "%#{escaped.downcase}%")
    end
    scope.limit(10).pluck(:id, :title).map { |id, title| { id: id, title: title } }
  end

  def set_role
    @role = Current.project.roles.includes(:skills, :approval_gates, :role_skills, :role_category, children: [ :skills, :role_category ]).find(params[:id])
  end

  def sync_approval_gates
    return unless params.dig(:role, :gates_submitted) == "1"

    raw_gates = params.dig(:role, :gates)
    gate_params = raw_gates ? raw_gates.permit(*ApprovalGate::GATABLE_ACTIONS) : ActionController::Parameters.new.permit!

    ApprovalGate::GATABLE_ACTIONS.each do |action_type|
      gate = @role.approval_gates.find_or_initialize_by(action_type: action_type)
      should_enable = gate_params[action_type] == "1"

      if should_enable
        gate.enabled = true
        gate.save!
      elsif gate.persisted?
        gate.update!(enabled: false)
      end
    end
  end

  def new_role_defaults
    return {} unless params[:role]

    params.require(:role).permit(:parent_id, :adapter_type, :working_directory, :role_category_id)
  end

  def reparent_child_id
    params[:reparent_child_id]
  end

  def role_params
    params.require(:role).permit(
      :title, :role_category_id, :description, :job_spec, :parent_id,
      :working_directory, :adapter_type, :heartbeat_enabled, :heartbeat_interval,
      :budget_dollars, :auto_hire_enabled,
      adapter_config: {}
    )
  end

  def apply_library_prefill(role, library_key)
    library_role = RoleLibrary::Registry.find(library_key)
    role.title         = library_role.title
    role.description   = library_role.description
    role.job_spec      = library_role.job_spec
    role.role_category = Current.project.role_categories.find_by(name: library_role.category)
  rescue RoleLibrary::Registry::RoleNotFound
    # Silently ignore unknown library keys — leave the form as-is.
  end

  def assign_library_skills(role, library_key)
    library_role = RoleLibrary::Registry.find(library_key)
    return if library_role.skill_keys.empty?

    skills_by_key = Current.project.skills.where(key: library_role.skill_keys).index_by(&:key)
    records = library_role.skill_keys.filter_map do |key|
      skill = skills_by_key[key]
      { role_id: role.id, skill_id: skill.id } if skill
    end
    RoleSkill.insert_all(records) if records.any?
  rescue RoleLibrary::Registry::RoleNotFound
    # Unknown library key — nothing to attach.
  end
end
