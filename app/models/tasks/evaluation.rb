module Tasks
  class Evaluation
    attr_reader :task

    def initialize(task)
      @task = task
    end

    def self.call(task)
      new(task).call
    end

    def call
      return unless task.completed?
      return if task.root?
      return if attempts_exhausted?

      result = evaluate
      evaluation = record_evaluation(result)

      if evaluation.fail?
        block_task(evaluation) if evaluation.attempt_number >= TaskEvaluation::MAX_ATTEMPTS
      end

      evaluation
    end

    private

    def evaluator_column
      @evaluator_column ||= task.column
    end

    def root_task
      @root_task ||= task.root_ancestor
    end

    def eval_count
      @eval_count ||= task.task_evaluations.count
    end

    def attempt_number
      eval_count + 1
    end

    def attempts_exhausted?
      eval_count >= TaskEvaluation::MAX_ATTEMPTS
    end

    def evaluate
      Agents::AiClient.chat(
        system: system_prompt,
        prompt: evaluation_prompt
      )
    end

    def system_prompt
      "You are evaluating whether a completed task advances its root mission. " \
      "Respond ONLY with valid JSON: {\"result\": \"pass\" or \"fail\", \"feedback\": \"2-3 sentence explanation\"}"
    end

    def evaluation_prompt
      parts = []
      parts << "## Root Task"
      parts << root_task.title
      parts << root_task.description if root_task.description.present?

      parts << ""
      parts << "## Completed Task"
      parts << "Title: #{task.title}"
      parts << "Description: #{task.description}" if task.description.present?

      work_output = task.messages.order(:created_at).limit(50).pluck(:body)
      if work_output.any?
        parts << ""
        parts << "## Work Output"
        work_output.each { |body| parts << body }
      end

      parts << ""
      parts << "Evaluate whether this task's output meaningfully advances the root task."

      parts.join("\n")
    end

    def record_evaluation(result)
      cost_cents = Agents::AiClient.estimate_cost_cents(result[:usage])

      evaluation = TaskEvaluation.create!(
        project_id: task.project_id,
        task: task,
        root_task: root_task,
        evaluator_column: evaluator_column,
        result: result[:parsed]["result"],
        feedback: result[:parsed]["feedback"],
        attempt_number: attempt_number,
        cost_cents: cost_cents
      )

      charge_cost(cost_cents)
      evaluation
    end

    def charge_cost(cost_cents)
      return unless cost_cents&.positive?
      new_cost = (task.cost_cents || 0) + cost_cents
      task.update_column(:cost_cents, new_cost)
    end

    def block_task(evaluation)
      post_feedback_message(evaluation)
      blocked = task.project.columns.find_by(system_key: "blocked")
      task.enter_column!(blocked, actor: evaluator_column, kind: :block, reason: evaluation.feedback) if blocked
      record_exhaustion_audit(evaluation)
    end

    def post_feedback_message(evaluation)
      Message.create!(
        task: task,
        author: evaluator_column,
        body: build_feedback_body(evaluation)
      )
    end

    def build_feedback_body(evaluation)
      status = evaluation.pass? ? "PASS" : "FAIL"
      parts = []
      parts << "## Task Evaluation — #{status} (Attempt #{evaluation.attempt_number}/#{TaskEvaluation::MAX_ATTEMPTS})"
      parts << ""
      parts << "**Root task:** #{root_task.title}"
      parts << ""
      parts << evaluation.feedback

      if evaluation.fail? && evaluation.attempt_number >= TaskEvaluation::MAX_ATTEMPTS
        parts << ""
        parts << "_Evaluation attempts exhausted. Task has been blocked for review._"
      end

      parts.join("\n")
    end

    def record_exhaustion_audit(evaluation)
      task.record_audit_event!(
        actor: evaluator_column,
        action: "task_evaluation_exhausted",
        project: task.project,
        metadata: {
          root_task_id: root_task.id,
          root_task_title: root_task.title,
          attempt_number: evaluation.attempt_number,
          feedback: evaluation.feedback
        }
      )
    end
  end
end
