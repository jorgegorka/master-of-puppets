class ChatSession::Pin < ApplicationRecord
  self.table_name = "chat_session_pins"

  belongs_to :chat_session
  belongs_to :user, default: -> { Current.user }
end
