module Skill::Enableable
  extend ActiveSupport::Concern

  class NotInstalled < StandardError; end

  included do
    has_many :enablements, class_name: "SkillEnablement", dependent: :destroy
    has_many :enabled_users, through: :enablements, source: :user
  end

  def enabled_for?(user)
    enablements.exists?(user_id: user.id)
  end

  def enable_for(user)
    transaction do
      if requires_installation? && !installed_for?(user)
        raise NotInstalled, "#{slug} (#{security_level}) requires explicit install_for(user)"
      end
      enablement = enablements.find_or_create_by!(user: user)
      track_event :enabled, user_id: user.id
      enablement
    end
  end

  def disable_for(user)
    enablement = enablements.find_by(user: user)
    return false unless enablement
    transaction do
      enablement.destroy
      track_event :disabled, user_id: user.id
    end
    true
  end

  private
    def requires_installation?
      %w[medium high].include?(security_level)
    end
end
