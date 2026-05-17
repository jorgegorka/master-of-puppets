class User < ApplicationRecord
  include Eventable

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one  :user_setting, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :chat_sessions, dependent: :destroy
  has_many :terminal_sessions, dependent: :destroy
  has_many :mcp_servers, dependent: :destroy
  has_many :scheduled_jobs, dependent: :destroy
  has_many :job_runs, through: :scheduled_jobs, source: :runs
  has_many :swarm_missions, dependent: :delete_all

  enum :role, member: 0, admin: 1

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  normalizes :email, with: -> { _1.to_s.downcase.strip }

  # The first user (single-user bootstrap, § 15.1) is admin so the install
  # works out of the box; subsequent users default to :member. The admin
  # column gates settings/providers and other privileged surfaces.
  before_validation :promote_bootstrap_to_admin, on: :create
  after_create :create_default_settings

  private
    def promote_bootstrap_to_admin
      return if User.exists?
      self.single_user_bootstrap = true if has_attribute?(:single_user_bootstrap)
      self.role = :admin
    end

    def create_default_settings
      create_user_setting! unless user_setting
    end
end
