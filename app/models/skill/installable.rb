module Skill::Installable
  extend ActiveSupport::Concern

  included do
    has_many :installations, class_name: "SkillInstallation", dependent: :destroy
    has_many :installers, through: :installations, source: :user
  end

  def installed_for?(user)
    installations.exists?(user_id: user.id)
  end

  def install_for(user)
    transaction do
      installation = installations.find_or_create_by!(user: user) do |i|
        i.accepted_security_level = Skill.security_levels[security_level]
      end
      track_event :installed, user_id: user.id, security_level: security_level
      installation
    end
  end

  def uninstall_for(user)
    installation = installations.find_by(user: user)
    return false unless installation
    transaction do
      installation.destroy
      track_event :uninstalled, user_id: user.id
    end
    true
  end
end
