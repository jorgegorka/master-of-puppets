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

  # Refresh the dashboard rollups (tokens-by-day, cost-by-model) for the
  # owning user whenever a message lands in `completed` — that's the only
  # status Dashboard::Rollup counts. The kwarg form of
  # `saved_change_to_status?` keeps this tight: it fires *only* on the
  # save that flips the status TO completed, not on every subsequent edit
  # of an already-completed row. We OR with `previously_new_record? && completed?`
  # to cover the (rare) case where a message is created already-completed.
  after_commit -> {
    user_id = chat_session.user_id
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard:#{user_id}",
      target:  "dashboard-rollups",
      partial: "dashboard/rollups",
      locals:  { rollup: Dashboard::Rollup.new(
        scope: Message.joins(:chat_session).where(chat_sessions: { user_id: user_id })
      ) }
    )
  }, if: -> { previously_new_record? ? completed? : saved_change_to_status?(to: "completed") }
end
