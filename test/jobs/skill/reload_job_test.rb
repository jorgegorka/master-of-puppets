require "test_helper"

class Skill::ReloadJobTest < ActiveJob::TestCase
  setup do
    @tmp = Dir.mktmpdir
    @prev = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    skills_root = Pathname.new(@tmp).join("skills/io/filesystem")
    skills_root.mkpath
    skills_root.join("SKILL.md").write(<<~MD)
      ---
      name: filesystem
      description: x
      category: io
      ---
      body
    MD
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev
  end

  test "perform with no path walks the workspace and reloads all skills" do
    Skill.delete_all
    Skill::ReloadJob.perform_now
    assert Skill.exists?(slug: "filesystem")
  end

  test "perform with a path loads only that file" do
    Skill.delete_all
    path = Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").to_s
    Skill::ReloadJob.perform_now(path: path)
    assert Skill.exists?(slug: "filesystem")
  end

  test "two enqueues for the same path produce one final row" do
    Skill.delete_all
    path = Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").to_s
    Skill::ReloadJob.perform_now(path: path)
    Skill::ReloadJob.perform_now(path: path)
    assert_equal 1, Skill.where(slug: "filesystem").count
  end

  test "concurrency_key disambiguates by path" do
    job_a = Skill::ReloadJob.new(path: "/tmp/a/SKILL.md")
    job_b = Skill::ReloadJob.new(path: "/tmp/b/SKILL.md")
    job_all = Skill::ReloadJob.new
    refute_equal job_a.concurrency_key, job_b.concurrency_key
    refute_equal job_a.concurrency_key, job_all.concurrency_key
    assert_match(/skill-reload:/, job_a.concurrency_key)
  end
end
