require "test_helper"
require "support/method_stub"

class TerminalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @captured_calls = []
    AgentsSupervisor::Client.singleton_class.alias_method(:__real_call, :call)
    AgentsSupervisor::Client.define_singleton_method(:call) do |method, params = {}, **|
      TerminalsControllerTest.last_calls << [ method, params ]
      { "ok" => true }
    end
    TerminalsControllerTest.last_calls = []
  end

  teardown do
    AgentsSupervisor::Client.singleton_class.alias_method(:call, :__real_call)
    AgentsSupervisor::Client.singleton_class.send(:remove_method, :__real_call)
  end

  class << self
    attr_accessor :last_calls
  end

  test "index lists non-terminated terminals" do
    get terminals_path
    assert_response :success
    assert_select "h1", "Terminals"
  end

  test "new renders the form" do
    get new_terminal_path
    assert_response :success
    assert_select "form"
  end

  test "create opens a terminal and redirects to show" do
    assert_difference -> { Current.user.terminal_sessions.count }, +1 do
      post terminals_path, params: { terminal_session: { cwd: "." } }
    end
    terminal = Current.user.terminal_sessions.order(:created_at).last
    assert_redirected_to terminal_path(terminal)
    assert terminal.live?
    assert_includes self.class.last_calls.map(&:first), "terminal.create"
  end

  test "create rejects path traversal in cwd" do
    assert_no_difference -> { Current.user.terminal_sessions.where.not(status: :terminated).count } do
      post terminals_path, params: { terminal_session: { cwd: "../../etc" } }
    end
    assert_redirected_to new_terminal_path
    assert_match(/Invalid working directory/, flash[:alert])
  end

  test "create does not leave an orphan :starting row when the supervisor fails" do
    AgentsSupervisor::Client.define_singleton_method(:call) do |method, params = {}, **|
      raise AgentsSupervisor::SupervisorError, "supervisor down" if method == "terminal.create"
      { "ok" => true }
    end

    before_count = Current.user.terminal_sessions.count
    assert_raises(AgentsSupervisor::SupervisorError) do
      post terminals_path, params: { terminal_session: { cwd: "." } }
    end
    assert_equal before_count, Current.user.terminal_sessions.count,
      "phantom :starting row should be cleaned up after supervisor failure"
  end

  test "show renders an active terminal" do
    terminal = users(:one).terminal_sessions.create!(cwd: ".", cols: 80, rows: 24, status: :live)
    get terminal_path(terminal)
    assert_response :success
    assert_match(/data-controller="terminal"/, response.body)
  end

  test "show redirects to index for a terminated terminal" do
    terminal = users(:one).terminal_sessions.create!(cwd: ".", cols: 80, rows: 24, status: :terminated)
    get terminal_path(terminal)
    assert_redirected_to terminals_path
  end

  test "destroy terminates and redirects" do
    terminal = users(:one).terminal_sessions.create!(cwd: ".", cols: 80, rows: 24, status: :live)
    delete terminal_path(terminal)
    assert_redirected_to terminals_path
    assert terminal.reload.terminated?
  end

  test "cross-tenancy: GET /terminals/<other-user-id> returns 404" do
    intruder = User.create!(email: "intruder-show@example.test", password: "supersecret123")
    intruder_terminal = intruder.terminal_sessions.create!(cwd: ".", cols: 80, rows: 24, status: :live)

    # Already signed in as users(:one); Current.user.terminal_sessions.find
    # raises RecordNotFound which Rails renders as 404 in integration tests.
    get terminal_path(intruder_terminal)
    assert_response :not_found
  end
end
