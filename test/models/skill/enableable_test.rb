require "test_helper"

class Skill::EnableableTest < ActiveSupport::TestCase
  test "enable_for safe skill works without installation" do
    skill = skills(:filesystem)  # safe
    user  = users(:one)
    skill.enable_for(user)
    assert skill.enabled_for?(user)
  end

  test "enable_for medium skill raises without installation" do
    skill = skills(:filesystem)
    skill.update!(security_level: :medium)
    assert_raises(Skill::Enableable::NotInstalled) do
      skill.enable_for(users(:one))
    end
  end

  test "enable_for medium skill succeeds after install_for" do
    skill = skills(:filesystem)
    skill.update!(security_level: :medium)
    user  = users(:one)
    skill.install_for(user)
    skill.enable_for(user)
    assert skill.enabled_for?(user)
  end

  test "disable_for removes the row" do
    skill = skills(:filesystem)
    user  = users(:one)
    skill.enable_for(user)
    skill.disable_for(user)
    refute skill.enabled_for?(user)
  end
end
