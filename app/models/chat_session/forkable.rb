module ChatSession::Forkable
  extend ActiveSupport::Concern

  def fork(at: messages.last, user: Current.user)
    transaction do
      child = user.chat_sessions.create!(
        title:       "#{title} (fork)",
        model:       model,
        provider:    provider,
        forked_from: self
      )
      messages.ordered.where("created_at <= ?", at.created_at).each do |m|
        child.messages.create!(
          role:           m.role,
          content_blocks: m.content_blocks,
          status:         :completed,
          model:          m.model,
          provider:       m.provider
        )
      end
      track_event :forked, child_id: child.id, at_message_id: at.id
      child
    end
  end
end
