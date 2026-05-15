class Message < ApplicationRecord
  include Eventable
  include Streamable
  include Costable
  include Forkable

  belongs_to :chat_session
  has_many :tool_calls, dependent: :destroy

  enum :role,   { system: 0, user: 1, assistant: 2, tool: 3 }
  enum :status, { pending: 0, streaming: 1, completed: 2, failed: 3, rate_limited: 4, cancelled: 5 }

  scope :streaming, -> { where(status: :streaming) }
  scope :done,      -> { where(status: %i[completed failed cancelled]) }
  scope :ordered,   -> { order(:created_at) }

  before_validation { self.content_blocks ||= [] }
end
