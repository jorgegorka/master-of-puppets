class ToolCall < ApplicationRecord
  include Eventable
  include Executable

  belongs_to :message
  has_many_attached :artifacts

  enum :source, { internal: 0, mcp: 1, skill: 2 }
  enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4 }

  scope :ordered, -> { order(:created_at) }
end
