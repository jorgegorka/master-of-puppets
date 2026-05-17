require "test_helper"

class SkillBroadcastTest < ActionCable::Channel::TestCase
  test "Skill#update broadcasts a turbo_stream replace to 'skills'" do
    skill = skills(:filesystem)
    assert_broadcasts("skills", 1) do
      skill.update!(name: "Filesystem v2")
    end
  end

  test "Skill#create broadcasts a turbo_stream replace to 'skills'" do
    assert_broadcasts("skills", 1) do
      Skill.create!(slug: "test-skill", name: "Test", category: "demo",
                    source_path: "/tmp/test/SKILL.md", body_digest: "deadbeef",
                    discovered_at: Time.current)
    end
  end
end
