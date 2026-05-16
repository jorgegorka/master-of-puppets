require "test_helper"

class SkillSearchTest < ActiveSupport::TestCase
  setup do
    fixture_attrs = skills(:filesystem).attributes.except("id", "created_at", "updated_at")
    Skill.delete_all  # clear fixture row so the test owns the table
    @fs    = Skill.create!(fixture_attrs)
    @debug = Skill.create!(
      fixture_attrs.merge(
        slug: "debug",
        name: "Debug",
        description: "Step through code with the debugger",
        body_digest: Digest::SHA256.hexdigest("debug"),
        source_path: Rails.root.join("test/fixtures/files/skills/debug/SKILL.md").to_s
      )
    )
    [@fs, @debug].each(&:reindex_fts!)
  end

  test "matching returns bm25-ordered skill results" do
    results = Skill.matching("debug")
    assert_equal [@debug.id], results.map(&:id)
  end

  test "matching is namespaced (skills don't return memory hits)" do
    MemoryFile.create!(
      path: "x.md",
      title: "Debugger",
      tags: [],
      content_digest: "d",
      byte_size: 0,
      disk_mtime: Time.current
    )
    results = Skill.matching("debug")
    results.each { |r| assert_kind_of Skill, r }
  end
end
