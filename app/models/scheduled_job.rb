class ScheduledJob < ApplicationRecord
  include Eventable
  include ScheduledJob::Pausable

  belongs_to :user, default: -> { Current.user }
  has_many :runs, class_name: "JobRun", dependent: :destroy

  validates :name, :cron, :prompt, :model, :provider, presence: true
  validates :name, uniqueness: { scope: :user_id }
  validate :cron_expression_parses

  before_validation :default_skill_slugs

  def cron_parser
    ScheduledJob::Cron.new(cron) if cron.present?
  rescue ScheduledJob::Cron::Invalid, ScheduledJob::Cron::TooFrequent
    nil
  end

  def compute_next_run_at(from: Time.current)
    cron_parser&.next_run_at(from: from)
  end

  private
    def default_skill_slugs
      self.skill_slugs ||= []
    end

    def cron_expression_parses
      return if cron.blank?

      ScheduledJob::Cron.new(cron)
    rescue ScheduledJob::Cron::Invalid, ScheduledJob::Cron::TooFrequent => e
      errors.add(:cron, e.message)
    end
end
