require "test_helper"

class Skill::InstallableTest < ActiveSupport::TestCase
  test "install_for is idempotent" do
    skill = skills(:filesystem)
    user  = users(:one)
    a = skill.install_for(user)
    b = skill.install_for(user)
    assert_equal a, b
    assert_equal 1, SkillInstallation.where(skill: skill, user: user).count
  end

  test "install_for records accepted_security_level + event" do
    skill = skills(:filesystem)
    user  = users(:one)
    assert_difference -> { Event.where(action: "skill_installed").count }, 1 do
      skill.install_for(user)
    end
    i = SkillInstallation.find_by(skill: skill, user: user)
    assert_equal Skill.security_levels[skill.security_level], i.accepted_security_level
  end

  test "uninstall_for removes the row + tracks event" do
    skill = skills(:filesystem)
    user  = users(:one)
    skill.install_for(user)
    assert_difference -> { Event.where(action: "skill_uninstalled").count }, 1 do
      skill.uninstall_for(user)
    end
    refute skill.installed_for?(user)
  end
end
