require "test_helper"
require "support/method_stub"

class TerminalChannelTest < ActionCable::Channel::TestCase
  setup do
    Current.session = sessions(:one)
    @user = users(:one)
    # Silence supervisor RPCs from #subscribed (attach + capture + pump).
    @client_calls = []
    AgentsSupervisor::Client.singleton_class.alias_method(:__real_call, :call) if AgentsSupervisor::Client.respond_to?(:call)
    AgentsSupervisor::Client.define_singleton_method(:call) do |method, params = {}, **opts|
      TerminalChannelTest.last_calls << [ method, params ]
      method == "terminal.capture" ? { "text" => "" } : { "ok" => true }
    end
    TerminalChannelTest.last_calls = []
  end

  teardown do
    if AgentsSupervisor::Client.respond_to?(:__real_call)
      AgentsSupervisor::Client.singleton_class.alias_method(:call, :__real_call)
      AgentsSupervisor::Client.singleton_class.send(:remove_method, :__real_call)
    end
  end

  class << self
    attr_accessor :last_calls
  end

  test "subscribes a user to their own terminal_session" do
    terminal = terminal_sessions(:detached_for_one)
    stub_connection current_user: @user
    subscribe terminal_session_id: terminal.id
    assert subscription.confirmed?
    assert_has_stream_for terminal
    assert terminal.reload.live?, "subscribed should attach! the session"
  end

  test "rejects subscription for someone else's terminal_session" do
    intruder = User.create!(email: "intruder-terminal@example.test", password: "supersecret123")
    stub_connection current_user: intruder
    subscribe terminal_session_id: terminal_sessions(:live_for_one).id
    assert subscription.rejected?
  end

  test "rejects subscription for a terminated terminal_session" do
    terminal = terminal_sessions(:live_for_one)
    terminal.update!(status: :terminated)
    stub_connection current_user: @user
    subscribe terminal_session_id: terminal.id
    assert subscription.rejected?
  end

  test "receive input forwards to Terminal::TmuxManager.send_keys via supervisor" do
    terminal = terminal_sessions(:detached_for_one)
    stub_connection current_user: @user
    subscribe terminal_session_id: terminal.id
    perform :receive, { "type" => "input", "data" => "echo hi\n" }
    assert_includes self.class.last_calls.map(&:first), "terminal.input"
  end

  test "receive resize forwards to Terminal::TmuxManager.resize via supervisor" do
    terminal = terminal_sessions(:detached_for_one)
    stub_connection current_user: @user
    subscribe terminal_session_id: terminal.id
    perform :receive, { "type" => "resize", "cols" => 100, "rows" => 50 }
    resize_calls = self.class.last_calls.select { |m, _| m == "terminal.resize" }
    assert_equal 1, resize_calls.size
    assert_equal 100, resize_calls.first.last[:cols]
    assert_equal 50, resize_calls.first.last[:rows]
  end
end
