class ChatSessions::ArchivesController < ApplicationController
  include ChatSessionScoped

  def create
    @chat_session.archive
    redirect_to chat_sessions_path
  end

  def destroy
    @chat_session.unarchive
    redirect_to @chat_session
  end
end
