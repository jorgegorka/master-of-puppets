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

  test "install_for rolls back the installation when track_event raises" do
    skill = skills(:filesystem)
    user  = users(:one)
    with_singleton_method(skill, :track_event, ->(*_a, **_kw) { raise "boom" }) do
      assert_raises(RuntimeError) { skill.install_for(user) }
    end
    refute skill.installed_for?(user),
      "installation row must roll back when track_event raises"
  end

  test "uninstall_for rolls back the destroy when track_event raises" do
    skill = skills(:filesystem)
    user  = users(:one)
    skill.install_for(user)
    with_singleton_method(skill, :track_event, ->(*_a, **_kw) { raise "boom" }) do
      assert_raises(RuntimeError) { skill.uninstall_for(user) }
    end
    assert skill.installed_for?(user),
      "installation row must remain when uninstall track_event raises"
  end
end
