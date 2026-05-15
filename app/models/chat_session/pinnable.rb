module ChatSession::Pinnable
  extend ActiveSupport::Concern

  included do
    has_one :pin_record, class_name: "ChatSession::Pin",
                         foreign_key: :chat_session_id,
                         dependent: :destroy
    scope :pinned,   -> { joins(:pin_record) }
    scope :unpinned, -> { where.missing(:pin_record) }
  end

  def pinned?
    pin_record.present?
  end

  def unpinned?
    !pinned?
  end

  def pin(user: Current.user)
    unless pinned?
      transaction do
        create_pin_record!(user: user)
        track_event :pinned, creator: user
      end
    end
  end

  def unpin(user: Current.user)
    if pinned?
      transaction do
        pin_record.destroy
        track_event :unpinned, creator: user
      end
    end
  end
end
