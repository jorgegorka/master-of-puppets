class Event < ApplicationRecord
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :eventable, polymorphic: true

  after_create_commit :notify_eventable

  private
    def notify_eventable
      eventable.try(:event_was_created, self)
    end
end
