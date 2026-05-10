class ReapStalledRunsJob < ApplicationJob
  queue_as :default

  STALL_THRESHOLD = 5.minutes

  def perform
    Run.where(status: :running)
       .where("last_activity_at < ?", STALL_THRESHOLD.ago)
       .includes(:task, :column, :project)
       .find_each { |run| reap(run) }
  end

  private

  def reap(run)
    elapsed = (Time.current - run.last_activity_at).to_i
    Rails.logger.warn("[ReapStalledRunsJob] reaping Run##{run.id} (#{elapsed}s since last activity)")

    run.finish!(status: :failed, error: StandardError.new("Reaped by watchdog: no activity for #{elapsed} seconds"))
    run.task&.post_system_comment(
      author: run.column,
      body: "My session was terminated by the watchdog after going silent."
    )
  rescue StandardError => e
    Rails.logger.error("[ReapStalledRunsJob] failed to reap Run##{run.id}: #{e.class}: #{e.message}")
  end
end
