module Tasks
  module Reviewing
    extend ActiveSupport::Concern

    class ReviewError < StandardError; end

    # Approve = move the task forward from a review column.
    def approve_by!(reviewer)
      raise ReviewError, "Task is not pending review" unless pending_review?

      Columns::Transition.new(task: self, actor: reviewer, kind: :advance).call!
    rescue ArgumentError => e
      raise ReviewError, e.message
    end

    # Reject = send the task back to the previous non-terminal column with feedback.
    def reject_by!(reviewer, feedback:)
      raise ReviewError, "Task is not pending review" unless pending_review?
      raise ReviewError, "Feedback is required when rejecting a task" if feedback.blank?

      ApplicationRecord.transaction do
        Columns::Transition.new(task: self, actor: reviewer, kind: :reject, feedback: feedback).call!
        messages.create!(author: reviewer, body: feedback, message_type: :comment)
      end
    rescue ArgumentError => e
      raise ReviewError, e.message
    end
  end
end
