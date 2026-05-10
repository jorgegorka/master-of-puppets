class Role::Detail
  attr_reader :role, :project

  def initialize(role, project)
    @role = role
    @project = project
  end

  def recent_heartbeats
    @recent_heartbeats ||= role.heartbeat_events.reverse_chronological.limit(5)
  end

  def project_skills
    @project_skills ||= project.skills.order(:category, :name)
  end

  def role_skills_by_skill_id
    @role_skills_by_skill_id ||= role.role_skills.index_by(&:skill_id)
  end

  def assigned_root_tasks
    @assigned_root_tasks ||= role.assigned_tasks.roots.by_priority
  end

  def eval_total
    @eval_total ||= role.task_evaluations.count
  end

  def eval_pass_count
    @eval_pass_count ||= role.task_evaluations.passed.count
  end

  def any_evaluations?
    eval_total > 0
  end

  def eval_pass_rate
    return 0 if eval_total.zero?
    (eval_pass_count.to_f / eval_total * 100).round
  end

  def timeline_entries(before: nil)
    Timeline.new(sources: timeline_sources, before: before)
  end

  private

  def timeline_sources
    [
      role.audit_events.includes(:actor),
      role.role_runs.includes(:task),
      role.task_evaluations.includes(:root_task)
    ]
  end
end
