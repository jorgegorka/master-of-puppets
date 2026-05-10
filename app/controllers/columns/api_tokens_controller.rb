class Columns::ApiTokensController < ApplicationController
  before_action :require_project!
  before_action :set_column

  def update
    unless @column.agent?
      redirect_to columns_path, alert: "Cannot rotate token on a manual column.", status: :see_other
      return
    end

    @column.regenerate_api_token!
    @column.record_audit_event!(actor: Current.user, action: "column_api_token_rotated", metadata: { column_id: @column.id })

    redirect_to edit_column_path(@column), notice: "API token rotated."
  end

  private

  def set_column
    @column = Current.project.columns.find(params[:column_id])
  end
end
