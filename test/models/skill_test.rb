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
end
