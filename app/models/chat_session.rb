class ChatSession < ApplicationRecord
  include Eventable
  include Archivable
  include Pinnable
  include Forkable

  belongs_to :user, default: -> { Current.user }
  belongs_to :forked_from, class_name: "ChatSession", optional: true

  has_many :messages, -> { order(:created_at) }, dependent: :destroy
  has_many :forks, class_name: "ChatSession", foreign_key: :forked_from_id, dependent: :nullify
  has_many :job_runs, dependent: :nullify

  validates :title, :model, :provider, presence: true

  before_create { self.last_active_at ||= Time.current }

  scope :active,       -> { unarchived }
  scope :pinned_first, -> {
    left_joins(:pin_record).order(Arel.sql("chat_session_pins.id IS NULL"), last_active_at: :desc)
  }
end
