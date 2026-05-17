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

  test "repeated load_from_path! with identical digest produces no broadcasts after the first" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "SKILL.md")
      body = "---\nname: temp-skill\ncategory: demo\n---\nbody text"
      File.write(path, body)

      fresh = Skill.new(source_path: path, origin: :builtin)
      assert_broadcasts("skills", 1) do
        fresh.load_from_path!
      end

      # Rapid-fire reloads with the same body: digest matches, should be no-op.
      assert_no_broadcasts("skills") do
        10.times { fresh.load_from_path! }
      end

      # Change the body: legitimate update → 1 broadcast.
      File.write(path, body + "\nmore text\n")
      assert_broadcasts("skills", 1) do
        fresh.load_from_path!
      end
    end
  end
end
