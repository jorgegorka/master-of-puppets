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
    [ @fs, @debug ].each do |s|
      s.reindex_fts_entry!(slug: s.slug, name: s.name, category: s.category,
                           description: s.description.to_s, body: s.body)
    end
  end

  test "matching returns bm25-ordered skill results" do
    results = Skill.matching("debug")
    assert_equal [ @debug.id ], results.map(&:id)
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

  test "destroying a skill clears its FTS row" do
    @debug.destroy
    row = SkillFts.connection.execute(
      ActiveRecord::Base.sanitize_sql([ "SELECT COUNT(*) AS c FROM skills_fts WHERE skill_id = ?", @debug.id ])
    ).first
    count_val = row.is_a?(Hash) ? row["c"] : row[0]
    assert_equal 0, count_val
  end

  test "rollback of update! inside load_from_path! leaves no stale FTS row" do
    tmp = Dir.mktmpdir
    skills_root = Pathname.new(tmp).join("skills/io/rollback")
    skills_root.mkpath
    skill_md = skills_root.join("SKILL.md")
    skill_md.write(<<~MD)
      ---
      name: rollback
      description: rolls back
      category: io
      ---
      v1 body
    MD
    skill = Skill.create!(
      slug: "rollback-pre",
      name: "rollback-pre",
      category: "io",
      source_path: skill_md.to_s,
      body_digest: "pre",
      manifest: {},
      discovered_at: 1.day.ago
    )
    skill.update_columns(body_digest: "different-from-disk")  # force the inner update! to fire

    # Stub track_event on this instance to raise inside the transaction.
    skill.define_singleton_method(:track_event) { |*_a, **_kw| raise "boom" }

    assert_raises(RuntimeError) { skill.load_from_path! }

    row = SkillFts.connection.execute(
      ActiveRecord::Base.sanitize_sql([
        "SELECT COUNT(*) AS c FROM skills_fts WHERE skill_id = ?", skill.id
      ])
    ).first
    count_val = row.is_a?(Hash) ? row["c"] : row[0]
    assert_equal 0, count_val, "FTS write must not happen when the AR transaction rolls back"
  ensure
    FileUtils.rm_rf(tmp) if tmp
  end
end
