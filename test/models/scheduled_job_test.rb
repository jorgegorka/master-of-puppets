require "test_helper"

class ScheduledJobTest < ActiveSupport::TestCase
  test "name is unique per user" do
    original = scheduled_jobs(:daily_digest)
    dup      = ScheduledJob.new(user: original.user, name: original.name, cron: "* * * * *",
                                prompt: "x", model: "claude-haiku-4-5", provider: "anthropic")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "Pausable: pause + resume + scopes" do
    job = scheduled_jobs(:daily_digest)
    assert job.active?

    job.pause(reason: "manual")
    assert job.reload.paused?
    assert_includes ScheduledJob.paused, job
    assert_not_includes ScheduledJob.active, job

    job.resume
    assert job.reload.active?
  end

  test "pause writes an Event with reason particulars" do
    job = scheduled_jobs(:daily_digest)
    assert_difference -> { job.events.where(action: "scheduled_job_paused").count }, +1 do
      job.pause(reason: "rate limit")
    end
    ev = job.events.where(action: "scheduled_job_paused").last
    assert_equal "rate limit", ev.particulars["reason"]
  end

  test "default_skill_slugs sets empty array when nil" do
    sj = ScheduledJob.new(user: users(:one), name: "Test", cron: "0 * * * *",
                          prompt: "x", model: "claude-haiku-4-5", provider: "anthropic")
    assert sj.valid?
    assert_equal [], sj.skill_slugs
  end
end
