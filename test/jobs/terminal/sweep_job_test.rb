require "test_helper"
require "support/method_stub"

class Terminal::SweepJobTest < ActiveJob::TestCase
  setup { Current.session = sessions(:one) }

  test "perform terminates sweepable rows" do
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) { { "ok" => true } }) do
      assert_equal 1, Terminal::SweepJob.new.perform
    end
    assert terminal_sessions(:stale_detached_for_one).reload.terminated?
  end

  test "is scheduled in recurring config" do
    cfg = YAML.load_file(Rails.root.join("config/recurring.yml"))
    assert_includes cfg.fetch("production").keys, "sweep_terminals"
    assert_equal "Terminal::SweepJob", cfg.dig("production", "sweep_terminals", "class")
  end
end
