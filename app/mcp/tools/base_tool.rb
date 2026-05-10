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
  end
end
