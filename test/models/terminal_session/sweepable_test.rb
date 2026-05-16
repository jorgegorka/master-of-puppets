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

  test "sweep! continues past a row whose terminate! raises an unexpected error" do
    other = users(:one).terminal_sessions.create!(cwd: Rails.root.to_s)
    other.update_columns(
      status: TerminalSession.statuses[:detached],
      last_activity_at: (TerminalSession::Sweepable::DETACH_TTL + 1.hour).ago
    )

    # Poison the first sweepable row's terminate! to raise an exception that
    # isn't on the supervisor-close swallow list. The sweep should log the
    # failure and keep going so a single bad row can't strand the rest.
    blown_id = TerminalSession.sweepable.order(:id).first.id
    original_terminate = TerminalSession.instance_method(:terminate!)
    TerminalSession.define_method(:terminate!) do
      raise ActiveRecord::RecordInvalid.new(self) if id == blown_id
      original_terminate.bind_call(self)
    end

    begin
      with_singleton_method(AgentsSupervisor::Client, :call, ->(*) { { "ok" => true } }) do
        assert_equal 1, TerminalSession.sweep!,
          "the surviving row should still be terminated when an earlier row's terminate! raises"
      end
    ensure
      TerminalSession.define_method(:terminate!, original_terminate)
    end
  end
end
