class ScheduledJob::Pause < ApplicationRecord
  self.table_name = "scheduled_job_pauses"

  belongs_to :scheduled_job
  belongs_to :user, default: -> { Current.user }
end
