require "test_helper"
require "support/method_stub"

class Terminal::TmuxManagerTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:one)
    @terminal_session = terminal_sessions(:live_for_one)
  end

  test "create calls terminal.create with WorkspacePath-resolved cwd + dims" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { captured = [ method, params ]; { "tmux_session_name" => "mop-term-1" } }) do
      Terminal::TmuxManager.create(@terminal_session)
    end
    assert_equal "terminal.create", captured[0]
    params = captured[1]
    assert_equal @terminal_session.id, params[:session_id]
    assert_equal @terminal_session.cols, params[:cols]
    assert_equal @terminal_session.rows, params[:rows]
    # cwd should resolve under MOP_HOME, not be the raw input
    assert params[:cwd].start_with?(Rails.application.config.x.mop_home.to_s),
      "expected cwd to be under MOP_HOME, got #{params[:cwd]}"
  end

  test "create raises WorkspacePath::EscapeAttempt for traversal probes" do
    @terminal_session.update!(cwd: "../../etc")
    with_singleton_method(AgentsSupervisor::Client, :call, ->(*, **) { fail "should not reach supervisor" }) do
      assert_raises WorkspacePath::EscapeAttempt do
        Terminal::TmuxManager.create(@terminal_session)
      end
    end
  end

  test "send_keys forwards to terminal.input" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { captured = [ method, params ]; {} }) do
      Terminal::TmuxManager.send_keys(@terminal_session, "echo hi\n")
    end
    assert_equal [ "terminal.input", { session_id: @terminal_session.id, data: "echo hi\n" } ], captured
  end

  test "resize forwards to terminal.resize with int dims" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { captured = [ method, params ]; {} }) do
      Terminal::TmuxManager.resize(@terminal_session, 100, 50)
    end
    assert_equal [ "terminal.resize", { session_id: @terminal_session.id, cols: 100, rows: 50 } ], captured
  end

  test "close forwards to terminal.close" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { captured = [ method, params ]; {} }) do
      Terminal::TmuxManager.close(@terminal_session)
    end
    assert_equal [ "terminal.close", { session_id: @terminal_session.id } ], captured
  end

  test "capture forwards to terminal.capture with default lines" do
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { captured = [ method, params ]; { "text" => "hi" } }) do
      result = Terminal::TmuxManager.capture(@terminal_session)
      assert_equal({ "text" => "hi" }, result)
    end
    assert_equal "terminal.capture", captured[0]
    assert_equal 500, captured[1][:lines]
  end
end
