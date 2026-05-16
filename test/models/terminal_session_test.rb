require "test_helper"
require "support/method_stub"

class TerminalSessionTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:one) }

  test "auto-assigns tmux_session_name on create" do
    t = users(:one).terminal_sessions.create!(cwd: Rails.root.to_s)
    assert_match(/\Amop-term-[0-9a-f]{8}\z/, t.tmux_session_name)
  end

  test "default_last_activity_at fills last_activity_at on create" do
    t = users(:one).terminal_sessions.create!(cwd: Rails.root.to_s)
    assert_not_nil t.last_activity_at
    assert_operator t.last_activity_at, :>, 1.minute.ago
  end

  test "tmux_session_name uniqueness is enforced" do
    a = users(:one).terminal_sessions.create!(cwd: Rails.root.to_s)
    b = users(:one).terminal_sessions.new(cwd: Rails.root.to_s, tmux_session_name: a.tmux_session_name)
    assert_not b.valid?
    assert_includes b.errors[:tmux_session_name], "has already been taken"
  end

  test "cwd presence is enforced" do
    t = users(:one).terminal_sessions.new
    assert_not t.valid?
    assert_includes t.errors[:cwd], "can't be blank"
  end

  test "attach! transitions to :live and tracks :attached event" do
    t = terminal_sessions(:detached_for_one)
    assert_difference -> { Event.where(action: "terminal_session_attached").count }, +1 do
      t.attach!
    end
    assert t.reload.live?
  end

  test "detach! transitions to :detached and tracks :detached event" do
    t = terminal_sessions(:live_for_one)
    assert_difference -> { Event.where(action: "terminal_session_detached").count }, +1 do
      t.detach!
    end
    assert t.reload.detached?
  end

  test "terminate! calls AgentsSupervisor::Client.call('terminal.close', ...) and transitions to :terminated" do
    t = terminal_sessions(:live_for_one)
    captured = nil
    with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params = {}, **) { captured = [method, params]; { "ok" => true } }) do
      assert_difference -> { Event.where(action: "terminal_session_terminated").count }, +1 do
        t.terminate!
      end
    end
    assert t.reload.terminated?
    assert_equal "terminal.close", captured[0]
    assert_equal t.id, captured[1][:session_id]
  end

  test "reattachable scope returns only :detached rows inside DETACH_TTL" do
    fresh = terminal_sessions(:detached_for_one)
    stale = terminal_sessions(:stale_detached_for_one)
    assert_includes TerminalSession.reattachable, fresh
    assert_not_includes TerminalSession.reattachable, stale
  end
end
