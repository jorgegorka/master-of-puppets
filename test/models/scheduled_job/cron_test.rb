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

  # Fugit shortcuts (named expressions)
  test "accepts @hourly" do
    cron = ScheduledJob::Cron.new("@hourly")
    from = Time.utc(2026, 5, 17, 12, 30, 0)
    assert_equal Time.utc(2026, 5, 17, 13, 0, 0), cron.next_run_at(from: from)
  end

  test "accepts @daily" do
    cron = ScheduledJob::Cron.new("@daily")
    from = Time.utc(2026, 5, 17, 12, 30, 0)
    assert_equal Time.utc(2026, 5, 18, 0, 0, 0), cron.next_run_at(from: from)
  end

  test "accepts @weekly" do
    assert_nothing_raised { ScheduledJob::Cron.new("@weekly") }
  end

  test "accepts @monthly" do
    assert_nothing_raised { ScheduledJob::Cron.new("@monthly") }
  end

  test "accepts @yearly" do
    assert_nothing_raised { ScheduledJob::Cron.new("@yearly") }
  end

  # Sub-minute second-resolution rejection
  test "rejects every-5-seconds with second field" do
    assert_raises(ScheduledJob::Cron::TooFrequent) { ScheduledJob::Cron.new("*/5 * * * * *") }
  end

  test "rejects every-30-seconds with second field" do
    assert_raises(ScheduledJob::Cron::TooFrequent) { ScheduledJob::Cron.new("*/30 * * * * *") }
  end

  # Borderline: exactly 60s is accepted (matches scheduler tick cadence)
  test "accepts every-minute (60s = MIN_INTERVAL_SECONDS)" do
    assert_nothing_raised { ScheduledJob::Cron.new("* * * * *") }
  end

  # Borderline: every 2 minutes is accepted
  test "accepts every-2-minutes" do
    assert_nothing_raised { ScheduledJob::Cron.new("*/2 * * * *") }
  end

  # Negative path: still raises Invalid on garbage including shortcut-look-alikes
  test "raises Invalid on @bogus" do
    assert_raises(ScheduledJob::Cron::Invalid) { ScheduledJob::Cron.new("@every_second") }
  end
end
