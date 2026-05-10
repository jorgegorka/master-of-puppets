class Roles::TimelineEntriesController < ApplicationController
  before_action :require_project!
  before_action :set_role

  def index
    @timeline = Role::Detail.new(@role, Current.project)
                            .timeline_entries(before: Timeline.parse_cursor(params[:before]))
    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def set_role
    @role = Current.project.roles.find(params[:role_id])
  end
end
