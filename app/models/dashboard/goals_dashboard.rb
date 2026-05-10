class Dashboard::GoalsDashboard
  attr_reader :project

  delegate :name, to: :project

  def initialize(project)
    @project = project
  end

  def goals
    @goals ||= project.tasks.roots.by_priority
      .includes(:column, :subtasks)
  end

  def attention
    @attention ||= Dashboard::AttentionItems.new(project)
  end
end
