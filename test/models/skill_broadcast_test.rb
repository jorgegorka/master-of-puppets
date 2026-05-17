require "test_helper"

class SkillBroadcastTest < ActionCable::Channel::TestCase
  test "Skill#update broadcasts a turbo_stream replace to 'skills'" do
    skill = skills(:filesystem)
    assert_broadcasts("skills", 1) do
      skill.update!(name: "Filesystem v2")
    end
  end
end
