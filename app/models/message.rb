class Message < ApplicationRecord
  include Triggerable
  include Chronological

  belongs_to :task
  belongs_to :author, polymorphic: true
  belongs_to :parent, class_name: "Message", optional: true
  belongs_to :column, optional: true
  belongs_to :run, optional: true

  has_many :replies, class_name: "Message", foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy

  enum :message_type, { comment: 0, question: 1, answer: 2 }

  validates :body, presence: true
  validate :parent_belongs_to_same_task
  validate :parent_message_exists

  scope :roots, -> { where(parent_id: nil) }

  after_commit :trigger_mention_wake, on: :create

  private

  def parent_belongs_to_same_task
    if parent.present? && parent.task_id != task_id
      errors.add(:parent, "must belong to the same task")
    end
  end

  def parent_message_exists
    if parent_id.present? && !Message.exists?(parent_id)
      errors.add(:parent, "message not found")
    end
  end

  def trigger_mention_wake
    project = task&.project
    return unless project

    mentioned_columns = detect_mentions(body, project)
    mentioned_columns.each do |column|
      next if column == author
      column.trigger_for(task, trigger_type: :task_entered)
    end
  end
end
