class TaskEvaluation < ApplicationRecord
  include Tenantable

  MAX_ATTEMPTS = 3

  belongs_to :task
  belongs_to :root_task, class_name: "Task"
  belongs_to :evaluator_column, class_name: "Column"
  belongs_to :evaluator_run, class_name: "Run", optional: true

  enum :result, { pass: 0, fail: 1 }

  validates :result, presence: true
  validates :feedback, presence: true
  validates :attempt_number, presence: true,
                             numericality: { only_integer: true, greater_than: 0 },
                             uniqueness: { scope: :task_id }
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :passed, -> { where(result: :pass) }
  scope :failed, -> { where(result: :fail) }
end
