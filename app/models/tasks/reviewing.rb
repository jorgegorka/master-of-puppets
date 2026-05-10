module Tasks
  module Reviewing
    extend ActiveSupport::Concern

    class ReviewError < StandardError; end

    # Approve = move the task forward from a review column.
    def approve_by!(reviewer)
      raise ReviewError, "Task is not pending review" unless pending_review?

      transition = Columns::Transition.new(task: self, actor: reviewer, kind: :advance)
      raise ReviewError, transition.errors.full_messages.to_sentence unless transition.valid?

      enter_column!(transition.target_column, actor: reviewer, kind: :advance)
    end

    # Reject = send the task back to the previous non-terminal column with feedback.
    def reject_by!(reviewer, feedback:)
      raise ReviewError, "Task is not pending review" unless pending_review?
      raise ReviewError, "Feedback is required when rejecting a task" if feedback.blank?

      transition = Columns::Transition.new(task: self, actor: reviewer, kind: :reject, feedback: feedback)
      raise ReviewError, transition.errors.full_messages.to_sentence unless transition.valid?

      ApplicationRecord.transaction do
        enter_column!(transition.target_column, actor: reviewer, kind: :reject, feedback: feedback)
        messages.create!(author: reviewer, body: feedback, message_type: :comment)
      end
    end
  end
end
