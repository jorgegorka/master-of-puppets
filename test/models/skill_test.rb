require "test_helper"

class SkillTest < ActiveSupport::TestCase
  test "slug uniqueness" do
    dup = Skill.new(skills(:filesystem).attributes.except("id"))
    refute dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "origin + security_level enums round-trip" do
    s = skills(:filesystem)
    assert s.builtin?
    assert s.safe?
  end

  test "enabled_for returns only skills enabled by the given user" do
    user_a = users(:one)
    user_b = users(:member)
    skill  = skills(:filesystem)
    skill.enable_for(user_a)

    assert_includes Skill.enabled_for(user_a).to_a, skill
    refute_includes Skill.enabled_for(user_b).to_a, skill
  end

  test "installed_for returns only skills installed by the given user" do
    user_a = users(:one)
    user_b = users(:member)
    skill  = skills(:filesystem)
    skill.install_for(user_a)

    assert_includes Skill.installed_for(user_a).to_a, skill
    refute_includes Skill.installed_for(user_b).to_a, skill
  end
end
