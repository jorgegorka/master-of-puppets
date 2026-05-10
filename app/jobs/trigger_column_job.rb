class TriggerColumnJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = Task.find_by(id: task_id)
    return unless task

    column = task.column
    return unless column&.agent?
    return if column.terminal?

    column.trigger_for(task, trigger_type: :task_entered)
  end
end
