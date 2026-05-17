class ScheduledJob < ApplicationRecord
  include Eventable
  include ScheduledJob::Pausable

  belongs_to :user, default: -> { Current.user }

  validates :name, :cron, :prompt, :model, :provider, presence: true
  validates :name, uniqueness: { scope: :user_id }

  before_validation :default_skill_slugs

  private
    def default_skill_slugs
      self.skill_slugs ||= []
    end
end
