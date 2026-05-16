class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat_session = current_user.chat_sessions.find_by(id: params[:chat_session_id])
    if chat_session
      stream_for chat_session
    else
      Rails.logger.info("[ChatChannel] reject: user=#{current_user.id} chat_session_id=#{params[:chat_session_id]}")
      reject
    end
  end
end
