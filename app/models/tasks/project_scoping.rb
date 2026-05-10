module Tasks
  module ProjectScoping
    extend ActiveSupport::Concern

    included do
      validate :column_belongs_to_same_project
      validate :parent_task_belongs_to_same_project
    end

    private

    def column_belongs_to_same_project
      if column.present? && column.project_id != project_id
        errors.add(:column, "must belong to the same project")
      end
    end

    def parent_task_belongs_to_same_project
      if parent_task.present? && parent_task.project_id != project_id
        errors.add(:parent_task, "must belong to the same project")
      end
    end
  end
end
