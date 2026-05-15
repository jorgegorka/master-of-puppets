module ChatSessionScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_chat_session
  end

  private
    def set_chat_session
      @chat_session = Current.user.chat_sessions.find(params[:chat_session_id] || params[:id])
    end
end
