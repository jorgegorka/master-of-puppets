class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat_session = current_user.chat_sessions.find(params[:chat_session_id])
    stream_for chat_session
  end
end
