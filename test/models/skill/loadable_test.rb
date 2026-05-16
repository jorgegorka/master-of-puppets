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
end
