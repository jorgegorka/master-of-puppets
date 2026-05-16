require "test_helper"
require "support/method_stub"

class TerminalSession::SweepableTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:one) }

  test "sweepable returns only detached rows past DETACH_TTL" do
    assert_includes TerminalSession.sweepable, terminal_sessions(:stale_detached_for_one)
    assert_not_includes TerminalSession.sweepable, terminal_sessions(:detached_for_one)
    assert_not_includes TerminalSession.sweepable, terminal_sessions(:live_for_one)
  end

  test "sweep! calls terminate! on each sweepable row" do
    calls = []
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { calls << [method, params]; { "ok" => true } }) do
      assert_equal 1, TerminalSession.sweep!
    end
    assert_equal ["terminal.close"], calls.map(&:first)
    assert terminal_sessions(:stale_detached_for_one).reload.terminated?
  end
end
