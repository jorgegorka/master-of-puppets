module ChatSession::Archivable
  extend ActiveSupport::Concern

  included do
    has_one :archive_record, class_name: "ChatSession::Archive",
                             foreign_key: :chat_session_id,
                             dependent: :destroy
    scope :archived,   -> { joins(:archive_record) }
    scope :unarchived, -> { where.missing(:archive_record) }
  end

  def archived?
    archive_record.present?
  end

  def unarchived?
    !archived?
  end

  def archived_by
    archive_record&.user
  end

  def archived_at
    archive_record&.created_at
  end

  def archive(user: Current.user)
    unless archived?
      transaction do
        create_archive_record!(user: user)
        track_event :archived, creator: user
      end
    end
  end

  def unarchive(user: Current.user)
    if archived?
      transaction do
        archive_record.destroy
        track_event :unarchived, creator: user
      end
    end
  end
end
