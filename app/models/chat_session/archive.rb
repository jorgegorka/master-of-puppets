class ChatSession::Archive < ApplicationRecord
  self.table_name = "chat_session_archives"

  belongs_to :chat_session
  belongs_to :user, default: -> { Current.user }
end
