class ScheduledJob < ApplicationRecord
  include Eventable
  include ScheduledJob::Pausable
  include ScheduledJob::Runnable

  belongs_to :user, default: -> { Current.user }
  has_many :runs, class_name: "JobRun", inverse_of: :scheduled_job, dependent: :destroy

  validates :name, :cron, :prompt, :model, :provider, presence: true
  validates :name, uniqueness: { scope: :user_id }
  validate :cron_expression_parses

  before_validation :default_skill_slugs
  before_validation :default_next_run_at, on: :create

  scope :due, ->(now = Time.current) { where.not(next_run_at: nil).where(next_run_at: ..now) }

  class << self
    def run_all_due(now: Time.current)
      active.due(now).find_each do |job|
        ScheduledJob::RunnerJob.perform_later(job)
      end
    end
  end

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

    def default_next_run_at
      return if next_run_at.present?

      self.next_run_at = compute_next_run_at
    end

    def cron_expression_parses
      return if cron.blank?

      ScheduledJob::Cron.new(cron)
    rescue ScheduledJob::Cron::Invalid, ScheduledJob::Cron::TooFrequent => e
      errors.add(:cron, e.message)
    end
end
