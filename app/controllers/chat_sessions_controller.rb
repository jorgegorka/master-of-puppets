class ChatSessionsController < ApplicationController
  before_action :set_chat_session, only: %i[show destroy]

  def index
    @chat_sessions = Current.user.chat_sessions.active.pinned_first
  end

  def show
  end

  def new
    @chat_session = Current.user.chat_sessions.build(
      title:    "New chat",
      model:    default_model,
      provider: "anthropic"
    )
  end

  def create
    @chat_session = Current.user.chat_sessions.create!(chat_session_params)
    redirect_to @chat_session
  end

  def destroy
    @chat_session.destroy
    redirect_to chat_sessions_path
  end

  private
    def set_chat_session
      @chat_session = Current.user.chat_sessions.find(params[:id])
    end

    def chat_session_params
      params.expect(chat_session: %i[title model provider])
    end

    def default_model
      ENV.fetch("MOP_DEFAULT_MODEL") { "claude-opus-4-7" }
    end
end
