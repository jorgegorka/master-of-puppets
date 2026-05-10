require "test_helper"

module Projects
  class SeedingTest < ActiveSupport::TestCase
    test "seed_default_columns! is invoked on project create" do
      project = Project.create!(name: "After Create Hook")
      assert_equal Projects::Seeding::DEFAULT_COLUMNS.size, project.columns.count
    end

    test "seed_default_columns! creates columns with the canonical attributes" do
      project = Project.create!(name: "Canonical Defaults")
      backlog = project.columns.find_by!(system_key: "backlog")
      assert_equal "Backlog", backlog.name
      assert_equal 1, backlog.position
      assert backlog.manual?
      assert_not backlog.terminal?
      assert_not backlog.hidden_by_default?

      in_progress = project.columns.find_by!(system_key: "in_progress")
      assert in_progress.agent?
      assert_equal 2, in_progress.position
      assert_nil in_progress.kind
      assert_nil in_progress.adapter_type, "in_progress is seeded unconfigured by design"

      review = project.columns.find_by!(system_key: "review")
      assert_equal "review", review.kind
      assert review.manual?

      done = project.columns.find_by!(system_key: "done")
      assert done.terminal?

      blocked = project.columns.find_by!(system_key: "blocked")
      assert blocked.hidden_by_default?

      cancelled = project.columns.find_by!(system_key: "cancelled")
      assert cancelled.terminal?
      assert cancelled.hidden_by_default?
    end

    test "seed_default_columns! is idempotent across explicit calls" do
      project = Project.create!(name: "Idempotent Cols")
      assert_no_difference("Column.count") do
        2.times { project.seed_default_columns! }
      end
    end

    test "seed_default_columns! preserves user-renamed system columns" do
      project = Project.create!(name: "Rename Test")
      project.columns.find_by!(system_key: "backlog").update!(name: "Inbox")
      assert_no_difference("Column.count") { project.seed_default_columns! }
      assert_equal "Inbox", project.columns.find_by(system_key: "backlog").name
    end

    test "seed_default_skills! loads every skill yml file as a builtin skill" do
      project = Project.create!(name: "Skills Project")
      expected = Project.default_skill_definitions.map { |d| d.fetch("key") }
      assert_equal expected.sort, project.skills.builtin.pluck(:key).sort
      assert project.skills.builtin.all?(&:builtin?)
    end

    test "seed_default_skills! is idempotent and does not clobber edits" do
      project = Project.create!(name: "Skill Edits")
      skill = project.skills.builtin.first
      skill.update!(markdown: "edited content")
      assert_no_difference("project.skills.count") { project.seed_default_skills! }
      assert_equal "edited content", skill.reload.markdown
    end

    test "default_skill_definitions caches the parsed YAML" do
      first = Project.default_skill_definitions
      second = Project.default_skill_definitions
      assert_same first, second
    end
  end
end
