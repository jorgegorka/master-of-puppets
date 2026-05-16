require "test_helper"

class Session::SweepJobTest < ActiveJob::TestCase
  setup { Current.session = sessions(:one) }

  test "perform deletes expired sessions" do
    sessions(:one).update_columns(expires_at: 1.day.ago)
    assert_difference -> { Session.count }, -1 do
      Session::SweepJob.new.perform
    end
  end

  test "is scheduled hourly in production config" do
    cfg = YAML.load_file(Rails.root.join("config/recurring.yml"))
    assert_includes cfg.fetch("production").keys, "sweep_expired_sessions"
    assert_equal "Session::SweepJob", cfg.dig("production", "sweep_expired_sessions", "class")
  end
end
