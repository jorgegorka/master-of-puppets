class ChatSessions::PinsController < ApplicationController
  include ChatSessionScoped

  def create
    @chat_session.pin
    redirect_to chat_sessions_path
  end

  def destroy
    @chat_session.unpin
    redirect_to chat_sessions_path
  end
end
