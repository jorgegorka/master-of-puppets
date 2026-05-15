module Message::Forkable
  extend ActiveSupport::Concern

  # Message-level fork (forks the whole chat session at this message).
  def fork(user: Current.user)
    chat_session.fork(at: self, user: user)
  end
end
