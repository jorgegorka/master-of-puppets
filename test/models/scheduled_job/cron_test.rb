require "test_helper"

class ScheduledJob::CronTest < ActiveSupport::TestCase
  test "parses a standard cron string" do
    cron = ScheduledJob::Cron.new("0 9 * * *")
    from = Time.utc(2026, 5, 17, 8, 0, 0)
    assert_equal Time.utc(2026, 5, 17, 9, 0, 0), cron.next_run_at(from: from)
  end

  test "raises Invalid on garbage" do
    assert_raises(ScheduledJob::Cron::Invalid) { ScheduledJob::Cron.new("definitely not cron") }
  end

  test "rejects sub-minute schedules (SchedulerTickJob fires every 60s)" do
    assert_raises(ScheduledJob::Cron::TooFrequent) { ScheduledJob::Cron.new("* * * * * *") }
  end

  test "accepts hourly cron" do
    cron = ScheduledJob::Cron.new("0 * * * *")
    from = Time.utc(2026, 5, 17, 12, 5, 0)
    assert_equal Time.utc(2026, 5, 17, 13, 0, 0), cron.next_run_at(from: from)
  end

  test "accepts every-minute cron" do
    assert_nothing_raised { ScheduledJob::Cron.new("* * * * *") }
  end
end
