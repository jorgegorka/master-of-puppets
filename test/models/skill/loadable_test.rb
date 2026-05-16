require "test_helper"

class Skill::LoadableTest < ActiveSupport::TestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    skills_root = Pathname.new(@tmp).join("skills/io/filesystem")
    skills_root.mkpath
    skills_root.join("SKILL.md").write(<<~MD)
      ---
      name: filesystem
      description: Read and write files.
      category: io
      allowed_tools: [read_file, write_file]
      ---
      # Filesystem
      Body here.
    MD
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "reload_from_disk does not tombstone existing rows when the skills tree is empty" do
    # Defensive guard against transient I/O / fresh-install-with-no-seeds. If
    # the disk walk turns up zero SKILL.md files, treat it as "no information"
    # and leave the DB untouched rather than nuking every row.
    existing = Skill.create!(
      slug: "keep-me", name: "Keep me", category: "io",
      source_path: Pathname.new(@tmp).join("skills/io/keep-me/SKILL.md").to_s,
      body_digest: "abc", discovered_at: 1.hour.ago, manifest: {}
    )
    FileUtils.rm_rf(Pathname.new(@tmp).join("skills"))
    Pathname.new(@tmp).join("skills").mkpath

    paths = Skill.reload_from_disk
    assert_empty paths
    assert Skill.exists?(existing.id), "must not destroy rows when disk walk is empty"
  end

  test "reload_from_disk creates one Skill per SKILL.md and tombstones missing ones" do
    stale = Skill.create!(
      slug: "ghost", name: "Ghost", category: "io",
      source_path: "vanished", body_digest: "0", discovered_at: 1.day.ago,
      manifest: {}
    )

    paths = Skill.reload_from_disk
    assert_equal 1, paths.length
    refute Skill.exists?(stale.id), "stale skill should be tombstoned"
    skill = Skill.find_by!(slug: "filesystem")
    assert_equal "Read and write files.", skill.description
    assert_equal "io", skill.category
    assert_equal %w[read_file write_file], skill.manifest["allowed_tools"]
  end

  test "load_from_path! is idempotent — same body, no event diff" do
    Skill.reload_from_disk
    skill = Skill.find_by!(slug: "filesystem")
    digest = skill.body_digest
    event_count = skill.events.count

    skill.load_from_path!
    assert_equal digest, skill.reload.body_digest
    assert_equal event_count, skill.events.count
  end

  test "missing frontmatter raises MalformedSkill" do
    Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").write("no frontmatter here")
    skill = Skill.new(source_path: Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").to_s)
    assert_raises(Skill::Loadable::MalformedSkill) { skill.load_from_path! }
  end

  test "#body raises MalformedSkill on a file with no frontmatter (parity with load_from_path!)" do
    Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").write("no frontmatter here")
    skill = Skill.new(source_path: Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").to_s)
    assert_raises(Skill::Loadable::MalformedSkill) { skill.body }
  end

  test "#body is memoized after load_from_path!" do
    Skill.destroy_all
    skill = Skill.new(source_path: Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").to_s)
    skill.load_from_path!
    Pathname.new(skill.source_path).delete  # if not memoized, the next call would raise Errno::ENOENT
    assert_nothing_raised { skill.body }
  end

  test "#body returns '' instead of raising when the source file has vanished" do
    # A fresh worker (no @body memo) rendering Skill#show 500s if the disk
    # file disappeared between reloads. Tolerate it — the next reload pass
    # tombstones the row.
    Skill.destroy_all
    path = Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md")
    skill = Skill.new(source_path: path.to_s)
    skill.load_from_path!
    skill_id = skill.id
    path.delete

    fresh = Skill.find(skill_id) # bypasses the @body memo
    assert_nothing_raised { fresh.body }
    assert_equal "", fresh.body
  end

  test "reload_path destroys the row when the source file has vanished" do
    # Watcher fires `skills.changed` for any change including deletes — the
    # ReloadJob path branch calls reload_path with the now-missing source.
    # Tombstone the orphan instead of crashing on Pathname#read.
    Skill.destroy_all
    path = Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md")
    Skill.reload_path(path.to_s)
    skill = Skill.find_by!(source_path: path.to_s)

    path.delete
    Skill.reload_path(path.to_s)

    refute Skill.exists?(skill.id), "orphaned row must be destroyed"
  end

  test "reload_path tolerates a malformed SKILL.md (logs and returns)" do
    bad = Pathname.new(@tmp).join("skills/io/broken/SKILL.md")
    bad.dirname.mkpath
    bad.write("no frontmatter here")
    assert_nothing_raised { Skill.reload_path(bad.to_s) }
    refute Skill.exists?(source_path: bad.to_s)
  end

  test "reload_from_disk tolerates a malformed SKILL.md and continues" do
    bad = Pathname.new(@tmp).join("skills/io/broken/SKILL.md")
    bad.dirname.mkpath
    bad.write("no frontmatter here")
    paths = nil
    assert_nothing_raised { paths = Skill.reload_from_disk }
    assert_includes paths, bad.to_s
    refute Skill.exists?(source_path: bad.to_s),
      "malformed SKILL.md should not produce a Skill row"
    assert Skill.exists?(slug: "filesystem"),
      "good SKILL.md should still load"
  end

  test "body with run_shell inside fenced code upgrades security_level to medium" do
    Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").write(<<~MD)
      ---
      name: filesystem
      description: x
      category: io
      security_level: safe
      ---
      Use the shell tool:

      ```
      run_shell "tar -czf foo.tar.gz foo"
      ```
    MD
    Skill.reload_from_disk
    assert_equal "medium", Skill.find_by!(slug: "filesystem").security_level
  end

  test "seeded filesystem SKILL.md resolves to security_level safe" do
    seed = Rails.root.join("db/seeds/skills/io/filesystem/SKILL.md")
    raise "seed SKILL.md missing" unless seed.exist?
    target = Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md")
    target.dirname.mkpath
    FileUtils.cp(seed, target)
    Skill.reload_from_disk
    skill = Skill.find_by!(slug: "filesystem")
    assert_equal "safe", skill.security_level,
      "well-documented safe skills must not get bumped to medium by prose backticks"
  end
end
