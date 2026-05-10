module Tools
  class BaseTool
    attr_reader :column

    def initialize(column)
      @column = column
    end

    def name
      raise NotImplementedError
    end

    def definition
      raise NotImplementedError
    end

    def call(arguments)
      raise NotImplementedError
    end

    private

    def project
      column.project
    end

    def active_run_for(task)
      Run.find_by(column: column, task: task, status: Run::ACTIVE_STATUSES)
    end

    def column_payload(col, task_count:)
      {
        id: col.id,
        name: col.name,
        position: col.position,
        transition_policy: col.transition_policy,
        kind: col.kind,
        terminal: col.terminal?,
        system_key: col.system_key,
        task_count: task_count
      }
    end

    def perform_transition(task_id:, kind:, reason: nil, feedback: nil, target_column_name: nil)
      task = project.tasks.find(task_id)
      run = active_run_for(task)
      raise ArgumentError, "No active run for this column on task #{task.id}" unless run

      moved_task = Columns::Transition.new(
        task: task,
        actor: run,
        kind: kind,
        reason: reason,
        feedback: feedback,
        target_column_name: target_column_name
      ).call!

      { status: "ok", task_id: task.id, to_column: moved_task.column.name }
    end
  end
end
