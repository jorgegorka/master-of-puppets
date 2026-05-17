require "test_helper"

class SearchableTest < ActiveSupport::TestCase
  test "Skill.reindex_fts_entry! writes a single row and clear_fts_entry! removes it" do
    skill = skills(:filesystem)
    skill.clear_fts_entry!
    assert_equal 0, SkillFts.where(skill_id: skill.id).count

    skill.reindex_fts_entry!(slug: skill.slug, name: skill.name, category: skill.category,
                             description: skill.description.to_s, body: "alpha bravo")
    assert_equal 1, SkillFts.where(skill_id: skill.id).count
    assert_includes SkillFts.where(skill_id: skill.id).pluck(:body), "alpha bravo"
  end

  test "MemoryFile.reindex_fts_entry! writes a single row keyed by memory_file_id" do
    file = memory_files(:index)
    file.clear_fts_entry!
    file.reindex_fts_entry!(path: file.path, title: file.title.to_s, tags: Array(file.tags).join(" "), body: "lorem ipsum")
    assert_equal 1, MemoryFileFts.where(memory_file_id: file.id).count
  end
end
