require "test_helper"

module Columns
  class PromptBuilderTest < ActiveSupport::TestCase
    setup do
      @column = columns(:acme_in_progress)
      @task   = tasks(:fix_login_bug)
    end

    test "manual columns return nil" do
      manual = columns(:acme_review)
      assert_nil manual.compose_unified_prompt(task: @task)
    end

    test "agent columns produce a non-empty prompt" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert prompt.present?
    end

    test "prompt includes column identity with project name and column name" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert_includes prompt, "## Your Column"
      assert_includes prompt, "**#{@column.name}**"
      assert_includes prompt, "**#{@column.project.name}**"
    end

    test "prompt includes job spec verbatim when present" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert_includes prompt, @column.job_spec
    end

    test "prompt includes success criteria section when present" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert_includes prompt, "## Success Criteria"
      assert_includes prompt, @column.success_criteria
    end

    test "prompt includes task title, id, description and focus rules" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert_includes prompt, "## Current Task"
      assert_includes prompt, "**Task ##{@task.id}: #{@task.title}**"
      assert_includes prompt, @task.description
      assert_includes prompt, "advance_task"
      assert_includes prompt, "reject_task"
      assert_includes prompt, "block_task"
    end

    test "prompt includes the skills catalog when the column has skills" do
      prompt = @column.compose_unified_prompt(task: @task)
      skill = skills(:acme_code_review)
      assert_includes prompt, "## Your Skills"
      assert_includes prompt, skill.name
      assert_includes prompt, skill.key
      assert_includes prompt, skill.markdown
    end

    test "prompt omits the skills section when no skills are attached" do
      @column.column_skills.destroy_all
      prompt = @column.reload.compose_unified_prompt(task: @task)
      refute_includes prompt, "## Your Skills"
    end

    test "prompt always ends with the tool affordances block" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert_includes prompt, "## Tools"
      assert_includes prompt, "advance_task"
      assert_includes prompt, "block_task"
      assert_includes prompt, "add_message"
    end

    test "prompt elides success criteria when the column has none" do
      @column.update_columns(success_criteria: nil)
      prompt = @column.reload.compose_unified_prompt(task: @task)
      refute_includes prompt, "## Success Criteria"
    end

    test "prompt embeds attached task documents as <document> blocks" do
      doc = documents(:acme_coding_standards)
      @task.task_documents.create!(document: doc)

      prompt = @column.compose_unified_prompt(task: @task.reload)
      assert_includes prompt, "## Reference Documents"
      assert_includes prompt, %(<document title="#{doc.title}">)
      assert_includes prompt, doc.body
    end

    test "prompt includes column description when present" do
      prompt = @column.compose_unified_prompt(task: @task)
      assert_includes prompt, @column.description
    end
  end
end
