module Columns
  module PromptBuilder
    extend ActiveSupport::Concern

    # Composes a unified prompt for the agent of this column.
    # Manual columns return nil (no agent runs there).
    def compose_unified_prompt(task:)
      return nil unless agent?

      parts = []
      parts << build_column_identity_prompt
      parts << job_spec if job_spec.present?
      parts << build_success_criteria_prompt if success_criteria.present?
      parts << build_task_prompt(task) if task
      parts << build_skills_prompt if skills.any?
      parts << build_tool_affordances_prompt
      parts.compact_blank.join("\n\n")
    end

    private

    def build_column_identity_prompt
      project_name = project&.name || "Unknown Project"
      <<~PROMPT.strip
        ## Your Column

        You are the **#{name}** column at **#{project_name}**.
        #{description.present? ? "\n#{description}\n" : ""}
      PROMPT
    end

    def build_success_criteria_prompt
      <<~PROMPT.strip
        ## Success Criteria

        #{success_criteria}
      PROMPT
    end

    def build_task_prompt(task)
      prompt = +"## Current Task\n\n"
      prompt << "**Task ##{task.id}: #{task.title}**\n"
      prompt << "\n#{task.description}\n" if task.description.present?

      task_documents = task.documents.to_a
      if task_documents.any?
        prompt << "\n## Reference Documents\n\n"
        prompt << task_documents.map { |d|
          "<document title=\"#{d.title}\">\n#{d.body}\n</document>"
        }.join("\n\n")
      end

      prompt << <<~FOCUS

        Focus rules:
        - Do work that delivers this column's success criteria for this task.
        - When the task meets the criteria, call `advance_task` to move it to the next column.
        - If the task should not proceed, call `reject_task` with feedback.
        - If you cannot proceed (missing info, blocker), call `block_task` with a reason.
      FOCUS

      prompt.strip
    end

    def build_skills_prompt
      catalog = skills.map { |s| "- **#{s.name}** (#{s.key}): #{s.description}" }.join("\n")
      details = skills.map { |s| "<skill key=\"#{s.key}\">\n#{s.markdown}\n</skill>" }.join("\n\n")

      <<~PROMPT.strip
        ## Your Skills

        #{catalog}

        ### Skill Instructions

        #{details}
      PROMPT
    end

    def build_tool_affordances_prompt
      <<~PROMPT.strip
        ## Tools

        - `advance_task(task_id, reason, to_column_name?)` — move task forward.
        - `reject_task(task_id, feedback, to_column_name?)` — send task back with feedback.
        - `block_task(task_id, reason)` — flag a blocker.
        - `add_message(task_id, body)` — comment on the task.
      PROMPT
    end
  end
end
