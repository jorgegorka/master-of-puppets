class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # GlobalID-serialized records that have been deleted between enqueue and
  # perform deserialize to ActiveJob::DeserializationError; for the *_later
  # pattern these jobs are best-effort, so dropping them is the right call.
  discard_on ActiveJob::DeserializationError
end
