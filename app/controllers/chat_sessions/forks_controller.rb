class ChatSessions::ForksController < ApplicationController
  include ChatSessionScoped

  def create
    at_message = @chat_session.messages.find(params.require(:message_id))
    child = @chat_session.fork(at: at_message)
    redirect_to child
  end
end
