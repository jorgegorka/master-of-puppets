module Columns
  module Triggering
    extend ActiveSupport::Concern

    def trigger_for(task, trigger_type: :task_entered, initiating_user: nil)
      return nil if manual?
      return nil unless runnable?

      run_attrs = {
        task: task,
        project: project,
        trigger_type: trigger_type.to_s,
        initiating_user: initiating_user,
        status: at_capacity? ? :throttled : :queued
      }

      run = runs.create!(run_attrs)
      ExecuteColumnJob.perform_later(run.id) if run.queued?
      run
    rescue ActiveRecord::RecordNotUnique
      runs.where(column: self, task: task, status: %w[queued throttled running]).first
    end

    def at_capacity?
      project_at_capacity? || column_at_capacity?
    end

    private

    def project_at_capacity?
      project.concurrent_agent_limit_reached?
    end

    def column_at_capacity?
      return false if max_concurrent_runs.to_i.zero?
      runs.where(status: %w[queued running]).count >= max_concurrent_runs
    end
  end
end
