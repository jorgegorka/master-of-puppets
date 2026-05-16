class TerminalsController < ApplicationController
  before_action :set_terminal_session, only: %i[show destroy]

  def index
    @terminal_sessions = Current.user.terminal_sessions.where.not(status: :terminated).order(updated_at: :desc)
  end

  def new
    @terminal_session = Current.user.terminal_sessions.new(cwd: ".", cols: 120, rows: 40)
  end

  def create
    @terminal_session = Current.user.terminal_sessions.create!(
      cwd:  params.dig(:terminal_session, :cwd).presence || ".",
      cols: 120,
      rows: 40
    )
    Terminal::TmuxManager.create(@terminal_session)
    @terminal_session.attach!
    redirect_to terminal_path(@terminal_session)
  rescue WorkspacePath::EscapeAttempt => e
    @terminal_session&.destroy
    redirect_to new_terminal_path, alert: "Invalid working directory: #{e.message}"
  end

  def show
    redirect_to terminals_path, alert: "Terminal already closed." and return if @terminal_session.terminated?
  end

  def destroy
    @terminal_session.terminate!
    redirect_to terminals_path, notice: "Terminal closed."
  end

  private
    def set_terminal_session
      @terminal_session = Current.user.terminal_sessions.find(params[:id])
    end
end
