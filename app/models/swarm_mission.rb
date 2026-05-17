class SwarmMission < ApplicationRecord
  include Eventable
  include Cancellable

  belongs_to :user,       default: -> { Current.user }
  belongs_to :created_by, class_name: "User", default: -> { Current.user }

  has_many :assignments, class_name: "SwarmAssignment",
                         inverse_of: :swarm_mission,
                         dependent: :destroy
  has_many :swarm_events, dependent: :destroy

  enum :state, { planning: 0, dispatching: 1, executing: 2, reviewing: 3,
                 blocked: 4, complete: 5, cancelled: 6 }
  enum :mode,  { auto: 0, manual: 1 }

  validates :title, presence: true
  validates :goal,  presence: true

  scope :active,    -> { where.not(state: %i[complete cancelled]) }
  scope :recent,    -> { order(created_at: :desc) }
  scope :for_user,  ->(u) { where(user: u) }
end
