class Tasks::TimelineEntriesController < ApplicationController
  before_action :require_project!
  before_action :set_task

  def index
    @timeline = Task::Detail.new(@task)
                            .timeline_entries(before: Timeline.parse_cursor(params[:before]))
    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def set_task
    @task = Current.project.tasks.find(params[:task_id])
  end
end
