# Phase 4 — MCP + Terminal + Supervisor v2

> **Executor:** Use `superpowers:subagent-driven-development` (or `superpowers:executing-plans`) to drive these tasks one at a time. Each `- [ ]` step has file paths, a failing test, the minimal impl, the verification command + expected output, and a commit. Tick the box as you complete each step.

**Parent plan:** [`docs/plans/workflows.md`](workflows.md) § Phase 4 (lines 3007–3024); supervisor protocol § 11 (758–808); frontend § 13 (833–861); security § 15 (871–923).

**Predecessors:** Phase 3 shipped at tag `phase-3` (commit `1a76d80`). One post-tag follow-up landed in `34bf9ce` ("Fix phase 3 issues."): vcr dropped, `Message::Streamable#needs_tool_loop?` treats `:failed` as resolved, and `Tool::Internal::WriteFile` blocks non-admins from writing under `skills/` or `profiles/`. Phase 4 starts from `HEAD == 34bf9ce` with a clean working tree.

**Goal:** the chat tool loop reaches external systems — configure an HTTP MCP server (e.g. context7) and call its tools from chat; open a terminal, run commands, disconnect, reattach within a TTL window with scrollback intact; expired web sessions are pruned hourly; the supervisor v2 hardens the JSON-RPC bridge so terminal + MCP traffic don't trample each other.

**Adds (high level):**

- `sessions.expires_at` migration + `Session::Sweepable` concern + `Session::SweepJob` (hourly).
- `terminal_sessions` migration + `TerminalSession` model + `TerminalSession::Sweepable` + `TerminalsController` + `TerminalChannel`.
- `Terminal::TmuxManager` service (shells out to `tmux`) + a stream pump (pipe-pane FIFO → channel broadcast) — both live inside the supervisor.
- `mcp_servers`, `mcp_tools` migrations + `McpServer` (with `Enableable` + `Discoverable`) + `McpTool` + `Mcp::HttpClient`.
- `Mcp::DiscoveryJob` + `McpServer#discover_tools!`.
- `Tool::Mcp` sibling registry (parallel to `Tool::Internal`) — `Message::Streamable#infer_source` restores the `:mcp` arm; `ToolCall::Executable` dispatches MCP invocations.
- `McpServersController` + nested `Tests` resource for "test connectivity" + views.
- Worker-0 gate for boot-replay jobs (`Skill::ReloadJob`, `Memory::FullReindexJob`) via Puma `on_worker_boot` + worker-index check. Replaces Phase 3's per-path concurrency-key stop-gap (the stop-gap stays as belt-and-braces — see Open items).
- `bin/agents_supervisor` v2: bounded `Concurrent::FixedThreadPool`, `MAX_RPC_LINE_BYTES` enforcement, per-connection bad-parse rate cap, single-writer-thread-per-connection (closes the line-99 TODO).
- `run_shell` rewrite: dispatch through new `shell.run` supervisor RPC; rlimits + uid drop where the OS supports it (Linux). Phase 3's prod-off flag + env scrub + PGID kill stay as the belt for macOS dev.
- `xterm`, `@xterm/addon-fit`, `@xterm/addon-search`, `@xterm/addon-web-links` importmap pins + `terminal_controller.js` Stimulus controller.
- CSP initializer activated (§ 15.7 — Phase 1 left this on the stock Rails comment stub).

**Phase 4 / Phase 4.5 split.** This doc bakes a scope-budget reality check. Workflows.md estimates "~2–3 weeks"; the surface as scoped is closer to four. The **must-ship spine** for Phase 4 (anchors the exit criteria) is: Session sweep, supervisor v2 threading hardening, MCP HTTP transport, Terminal slice, Worker-0 gate, CSP activation, `McpTool` branch restore, `run_shell` rlimits/uid drop. The **Phase 4.5 candidates** (defer if scope balloons; the exit criteria still hold without them) are: MCP **stdio** bridge, Monaco editor upgrade, Action Cable cursor-replay-from-message-cursor, Linux namespaces for `run_shell`. Tasks tagged **`(4.5 candidate)`** below are slip-eligible.

**Exit criteria:** see Task 4.16.

---

## Task 4.0 — Phase 3 epilogue + Phase 4 baseline

The 3.16 hardening batch closed at tag `phase-3` (`1a76d80`). Commit `34bf9ce` ("Fix phase 3 issues.") landed on top as a thin follow-up. Before starting Phase 4 work, sanity-check the baseline so a regression doesn't get blamed on Phase 4 code.

- [ ] **Step 1: Confirm clean tree at `34bf9ce`.**

  ```bash
  git status
  git log --oneline -5
  git tag --list 'phase-*'
  ```

  Expected: working tree clean; `34bf9ce` at HEAD; tags include `phase-2-final` and `phase-3`. No `phase-3-final` exists (Task 3.16 reverted to plain `phase-3` after retag — workflows.md decisions logged from Phase 3 review).

- [ ] **Step 2: Green test baseline before any Phase 4 code.**

  ```bash
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```

  Expected: tests green (≥260 runs / 697 assertions / 0 failures / 1 skip — the `tool_loop_round_trip` cassette skip is gone after the vcr removal in `34bf9ce`; recount on first run). Brakeman: the 11 Medium/File-Access warnings carried from Phase 3 (`WorkspacePath`-protected). Bundler-audit: 0 vulnerabilities.

  Pin the numbers in your scratchpad — Task 4.16's verification compares against this baseline, not against the workflows.md doc.

---

## Task 4.1 — `sessions.expires_at` migration + `Session::Sweepable` concern

Phase 1 shipped permanent cookies and no DB-side expiry (`app/controllers/sessions_controller.rb` uses `cookies.signed.permanent`; `app/models/session.rb` is 5 lines, no `expires_at`). Single-user installs are fine with this per § 15.1, but multi-user installs need expiry before sign-ups open — workflows.md:3016. The schema migration is greenfield (verified against `db/schema.rb:121–129`).

- [ ] **Step 1: Migration.**

  ```bash
  bin/rails g migration AddExpiresAtToSessions
  ```

  Edit `db/migrate/<ts>_add_expires_at_to_sessions.rb`:

  ```ruby
  class AddExpiresAtToSessions < ActiveRecord::Migration[8.1]
    def change
      add_column :sessions, :expires_at, :datetime
      Session.reset_column_information
      Session.in_batches.update_all("expires_at = COALESCE(last_seen_at, created_at) + #{30 * 24 * 3600}")
      change_column_null :sessions, :expires_at, false
      add_index :sessions, :expires_at
    end
  end
  ```

  Run `bin/rails db:migrate db:test:prepare`.

- [ ] **Step 2: `Session::Sweepable` concern.** New file `app/models/session/sweepable.rb`:

  ```ruby
  module Session::Sweepable
    extend ActiveSupport::Concern

    DEFAULT_TTL_DAYS  = ENV.fetch("MOP_SESSION_TTL_DAYS", "30").to_i
    DEFAULT_TTL       = DEFAULT_TTL_DAYS.days
    ROTATION_WINDOW   = DEFAULT_TTL / 3  # last third of TTL → rotate on use
    CLOCK_SKEW_MARGIN = 60.seconds

    included do
      before_create { self.expires_at ||= Time.current + DEFAULT_TTL }

      scope :expired, -> { where("expires_at < ?", Time.current - CLOCK_SKEW_MARGIN) }
      scope :active,  -> { where("expires_at >= ?", Time.current) }
    end

    def expired?
      expires_at <= Time.current
    end

    def expire!
      transaction do
        update!(expires_at: Time.current)
        track_event :expired
      end
    end

    def touch_and_maybe_rotate!
      now    = Time.current
      rotate = (expires_at - now) < ROTATION_WINDOW
      attrs  = { last_seen_at: now }
      attrs[:expires_at] = now + DEFAULT_TTL if rotate
      update_columns(attrs)  # bypass callbacks for the per-request hot path
      track_event :rotated if rotate
    end

    class_methods do
      def sweep!
        expired.find_each(&:destroy).size
      end
    end
  end
  ```

  Wire into `app/models/session.rb`:

  ```ruby
  class Session < ApplicationRecord
    include Eventable
    include Sweepable

    belongs_to :user
    before_create { self.last_seen_at ||= Time.current }
  end
  ```

- [ ] **Step 3: Failing test.** New `test/models/session/sweepable_test.rb`:

  ```ruby
  require "test_helper"

  class Session::SweepableTest < ActiveSupport::TestCase
    setup { Current.session = sessions(:one) }

    test "before_create defaults expires_at to DEFAULT_TTL from now" do
      s = users(:alice).sessions.create!(user_agent: "ua", ip_address: "127.0.0.1")
      assert_in_delta Session::Sweepable::DEFAULT_TTL.from_now.to_i, s.expires_at.to_i, 5
    end

    test "expired? is true past expires_at" do
      s = sessions(:one).tap { |r| r.update_columns(expires_at: 1.minute.ago) }
      assert s.expired?
    end

    test "expire! sets expires_at to now and tracks :expired event" do
      s = sessions(:one)
      assert_difference -> { Event.where(action: "expired").count }, +1 do
        s.expire!
      end
      assert s.expired?
    end

    test "touch_and_maybe_rotate! bumps last_seen_at without rotating outside window" do
      s = sessions(:one)
      s.update_columns(expires_at: Session::Sweepable::DEFAULT_TTL.from_now, last_seen_at: 1.day.ago)
      original_expires = s.expires_at
      s.touch_and_maybe_rotate!
      s.reload
      assert_operator s.last_seen_at, :>, 1.minute.ago
      assert_equal original_expires.to_i, s.expires_at.to_i  # not rotated
    end

    test "touch_and_maybe_rotate! extends expires_at inside rotation window" do
      s = sessions(:one)
      window = Session::Sweepable::ROTATION_WINDOW
      s.update_columns(expires_at: (window - 1.hour).from_now)
      assert_difference -> { Event.where(action: "rotated").count }, +1 do
        s.touch_and_maybe_rotate!
      end
      assert_operator s.reload.expires_at, :>, window.from_now
    end

    test "sweep! deletes expired rows only" do
      sessions(:one).update_columns(expires_at: 1.day.ago)
      sessions(:two).update_columns(expires_at: 1.day.from_now)
      assert_difference -> { Session.count }, -1 do
        Session.sweep!
      end
    end
  end
  ```

  Run:

  ```bash
  bin/rails test test/models/session/sweepable_test.rb
  ```

  Expected: 6 runs / ≥10 assertions / 0 failures.

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.1: sessions.expires_at + Session::Sweepable (TTL + rotation + sweep!)
  ```

---

## Task 4.2 — Authentication path: expiry check + `last_seen_at` rotation

`ApplicationController#set_current` today is `Session.find_by(id: cookies.signed[:session_id])` with **no expiry check** and **no rotation** of `last_seen_at` (verified against `app/controllers/application_controller.rb`). The Phase 4 contract: expired sessions redirect to sign-in; valid sessions get `touch_and_maybe_rotate!` on every authenticated request.

- [ ] **Step 1: Failing controller test.** Add to `test/controllers/application_controller_test.rb` (create if absent):

  ```ruby
  require "test_helper"

  class ApplicationControllerTest < ActionDispatch::IntegrationTest
    test "expired session redirects to sign-in with flash" do
      session = sessions(:one)
      session.update_columns(expires_at: 1.minute.ago)
      sign_in_as_session(session)
      get root_path
      assert_redirected_to new_session_path
      assert_equal "Session expired. Please sign in again.", flash[:alert]
    end

    test "valid session bumps last_seen_at on each request" do
      session = sessions(:one)
      session.update_columns(last_seen_at: 1.day.ago, expires_at: 1.year.from_now)
      sign_in_as_session(session)
      get root_path
      assert_response :success
      assert_operator session.reload.last_seen_at, :>, 1.minute.ago
    end
  end
  ```

  Add `sign_in_as_session(session)` to `test/test_helper.rb` if the existing `sign_in_as` doesn't accept a Session record. (The Phase 1 helper at `test_helper.rb:60–80` mints a Session inline; refactor to accept either a User or a Session.)

  Run:

  ```bash
  bin/rails test test/controllers/application_controller_test.rb
  ```

  Expected: 2 failures (no expiry check, no rotation).

- [ ] **Step 2: Wire into `set_current`.** Edit `app/controllers/application_controller.rb`:

  ```ruby
  def set_current
    session = Session.find_by(id: cookies.signed[:session_id])
    if session&.expired?
      session.destroy
      cookies.delete(:session_id)
      flash[:alert] = "Session expired. Please sign in again."
      Current.session = Current.user = nil
      redirect_to(new_session_path) and return
    end
    Current.session    = session
    Current.user       = session&.user
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
    session&.touch_and_maybe_rotate!
  end
  ```

  Mirror the expiry-and-destroy step in `app/channels/application_cable/connection.rb` so a stale cookie can't open an Action Cable subscription: reject the connection if the resolved session is expired.

- [ ] **Step 3: Cookie expiry alignment (optional, low priority).** `cookies.signed.permanent` (20-year cookie) plus a 30-day DB row is functional but misleading. **Decision deferred to Open items** — the DB row is the gate.

- [ ] **Step 4: Green.** Re-run the test from Step 1 → 2 passes. Run full test suite to catch any test fixture that relied on the no-expiry behaviour: `bin/rails test`.

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.2: authentication path — reject expired sessions, rotate last_seen_at on use
  ```

---

## Task 4.3 — `Session::SweepJob` recurring

- [ ] **Step 1: Job.** `app/jobs/session/sweep_job.rb`:

  ```ruby
  class Session::SweepJob < ApplicationJob
    queue_as :default
    def perform = Session.sweep!
  end
  ```

- [ ] **Step 2: Recurring schedule.** Edit `config/recurring.yml`:

  ```yaml
  production:
    sweep_expired_sessions:
      class: Session::SweepJob
      schedule: every hour at minute 7
  ```

  (Mirror the dev block if Phase 1 added one.)

- [ ] **Step 3: Test.** `test/jobs/session/sweep_job_test.rb`:

  ```ruby
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
      assert_includes cfg.dig("production").keys, "sweep_expired_sessions"
    end
  end
  ```

  Run:

  ```bash
  bin/rails test test/jobs/session/sweep_job_test.rb
  ```

  Expected: 2 runs / 2 assertions / 0 failures.

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.3: Session::SweepJob recurring hourly
  ```

---

## Task 4.4 — Worker-0 gate for boot-replay jobs

Today two enqueue sites fire boot-replay jobs from **every Puma worker**:

- `config/initializers/agents_supervisor_client.rb:20–24` — `Memory::FullReindexJob.perform_later` + `Skill::ReloadJob.perform_later`.
- `config/initializers/workspace_bootstrap.rb:42–49` — `Skill::ReloadJob.perform_later`.

Phase 3 Task 3.16a added `limits_concurrency` to `Skill::ReloadJob` to collapse the fan-out (`app/jobs/skill/reload_job.rb`). `Memory::FullReindexJob` has no such gate and relies on digest idempotency in `MemoryFile#reindex!`. Cheaper fix: enqueue only from worker 0.

Decision: **keep the per-path `limits_concurrency` as belt-and-braces** (cost is one extra fast check per enqueue; eliminates fan-out from non-cluster Pumas, `bin/rails console`, `bin/rails runner`, etc.).

- [ ] **Step 1: Puma `on_worker_boot` exposes worker index.** Edit `config/puma.rb`:

  ```ruby
  on_worker_boot do |index|
    ENV["PUMA_WORKER_INDEX"] = index.to_s
  end
  ```

  (`index` is Puma's 0-based worker index inside cluster mode. Single-mode Puma never calls `on_worker_boot`; the env stays unset → `to_i` → `0` → gate passes, which is the desired single-worker behaviour.)

- [ ] **Step 2: Gate the enqueues.** Edit `config/initializers/agents_supervisor_client.rb` so the `Memory::FullReindexJob` + `Skill::ReloadJob` enqueues live behind:

  ```ruby
  next unless boot_replay_leader?

  AgentsSupervisor::Client.subscribe_to_memory_changes
  Memory::FullReindexJob.perform_later
  Skill::ReloadJob.perform_later
  ```

  Helper at the top of the initializer:

  ```ruby
  def boot_replay_leader?
    # Single-worker Puma never sets PUMA_WORKER_INDEX, so it always replays.
    # Cluster Puma only enters this branch from worker 0.
    ENV.fetch("PUMA_WORKER_INDEX", "0").to_i.zero?
  end
  ```

  Same edit in `config/initializers/workspace_bootstrap.rb` (gate the `Skill::ReloadJob.perform_later` line; leave the seed-copy work running on every worker because the disk write is idempotent — `mkdir_p` + `cp` on identical bytes is a no-op).

- [ ] **Step 3: Test.** `test/initializers/boot_replay_test.rb` (or extend the existing `agents_supervisor_client_test.rb`):

  ```ruby
  require "test_helper"

  class BootReplayGateTest < ActiveSupport::TestCase
    test "non-leader worker does not enqueue boot replay" do
      ENV["PUMA_WORKER_INDEX"] = "1"
      assert_no_enqueued_jobs only: [Skill::ReloadJob, Memory::FullReindexJob] do
        load Rails.root.join("config/initializers/agents_supervisor_client.rb")
      end
    ensure
      ENV.delete("PUMA_WORKER_INDEX")
    end

    test "worker 0 enqueues boot replay" do
      ENV["PUMA_WORKER_INDEX"] = "0"
      assert_enqueued_jobs 2, only: [Skill::ReloadJob, Memory::FullReindexJob] do
        load Rails.root.join("config/initializers/agents_supervisor_client.rb")
      end
    ensure
      ENV.delete("PUMA_WORKER_INDEX")
    end
  end
  ```

  Run; expected: 2 runs / 2 assertions / 0 failures. (You may need to stub the `Listen.to` constructor in the initializer; mirror whatever the Phase 2 supervisor tests do.)

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.4: worker-0 boot-replay gate via Puma on_worker_boot
  ```

---

## Task 4.5 — Supervisor v2: thread pool, line-byte cap, bad-parse rate cap, single-writer

`bin/agents_supervisor` is 125 lines at HEAD; the threading model is **unbounded `Thread.new(client)`** at `bin/agents_supervisor:107`, and the line-99 TODO breadcrumb explicitly calls out:

> "TODO(phase-4): one socket carries BOTH request/response traffic AND the fan-out notification stream. The per-connection reader thread below and the listener-fan-out loop above both write to `client`, which can interleave under load."

Phase 4 closes this. **Decision:** stay on plain threads + `IO.select`. Workflows.md:773 + § 19 default. Adding `async` is a significant test-surface migration with no concrete latency motivation yet — surface as an Open item if pump latency proves bad under terminal load.

- [ ] **Step 1: Failing supervisor integration test.** New `test/integration/supervisor_v2_test.rb`:

  ```ruby
  require "test_helper"
  require "socket"

  class SupervisorV2Test < ActiveSupport::TestCase
    SOCKET = Rails.root.join("tmp/sockets/agents_supervisor_test.sock")

    setup do
      FileUtils.rm_f(SOCKET)
      @pid = spawn({ "MOP_SUPERVISOR_SOCKET" => SOCKET.to_s }, Rails.root.join("bin/agents_supervisor").to_s)
      sleep 0.5 until SOCKET.exist?
    end

    teardown do
      Process.kill("TERM", @pid)
      Process.wait(@pid)
      FileUtils.rm_f(SOCKET)
    end

    test "rejects a request line over MAX_RPC_LINE_BYTES" do
      s = UNIXSocket.open(SOCKET.to_s)
      s.write("x" * (64 * 1024 + 10) + "\n")
      response = s.gets
      assert_match(/-32700|line too long/i, response)  # parse error
      assert_raises(IOError, EOFError) { s.read }      # connection closed
    end

    test "bad-parse rate cap closes the connection after N malformed lines" do
      s = UNIXSocket.open(SOCKET.to_s)
      6.times { s.write("not-json\n") }
      sleep 0.1
      assert_raises(Errno::EPIPE, IOError) { 50.times { s.write("not-json\n") } }
    end

    test "health.ping returns pong" do
      s = UNIXSocket.open(SOCKET.to_s)
      s.write({ jsonrpc: "2.0", id: 1, method: "health.ping" }.to_json + "\n")
      response = JSON.parse(s.gets)
      assert response.dig("result", "pong")
    end
  end
  ```

  Run; expected: all 3 fail until Step 2 lands (or 2 fail; `health.ping` already passes).

- [ ] **Step 2: Bound the thread pool + enforce caps.** Edit `bin/agents_supervisor` (`:95–123` is the rewrite target):

  Top of file:

  ```ruby
  MAX_RPC_LINE_BYTES   = Integer(ENV.fetch("MOP_RPC_MAX_LINE", 64 * 1024))
  BAD_PARSE_CAP        = Integer(ENV.fetch("MOP_RPC_BAD_PARSE_CAP", 5))
  BAD_PARSE_WINDOW     = Float(ENV.fetch("MOP_RPC_BAD_PARSE_WINDOW", 10))
  POOL_SIZE            = Integer(ENV.fetch("MOP_SUPERVISOR_POOL", 16))
  SUPERVISOR_SOCKET    = ENV.fetch("MOP_SUPERVISOR_SOCKET", Rails.root.join("tmp/sockets/agents_supervisor.sock").to_s)

  dispatcher = Concurrent::FixedThreadPool.new(POOL_SIZE)
  ```

  Replace the per-connection `Thread.new(client)` loop with a `ConnectionPump` PORO that owns:

  - one reader thread per connection (drains `c.each_line` line-by-line, enforces `MAX_RPC_LINE_BYTES` via `each_line(limit: MAX_RPC_LINE_BYTES + 1)` then `raise LineTooLong` if a line exceeds);
  - a per-connection `bad_parse_window = []` (`Time.now` push on parse error; trim entries older than `BAD_PARSE_WINDOW`; close socket when `size >= BAD_PARSE_CAP`);
  - a per-connection write queue (`SizedQueue.new(256)`) drained by one writer thread per connection — both the reader's response and the notification fan-out enqueue here, so writes never interleave;
  - dispatch handler-work via `dispatcher.post { … }` so a slow handler can't block the reader.

  Notification fan-out (memory-watcher, skills-watcher) writes to **each connection's write queue**, not to the socket directly. The old direct-write code at `bin/agents_supervisor:42–53` and `:58–69` becomes a `connections.each { |conn| conn.notify(payload) }` call.

  Graceful shutdown additions: `dispatcher.shutdown; dispatcher.wait_for_termination(5)` before exit.

- [ ] **Step 3: Make supervisor socket path env-configurable.** Already done if you read `MOP_SUPERVISOR_SOCKET` above. Update `app/services/agents_supervisor/client.rb` to consult the same env var so the test can point at a sandbox socket without monkey-patching `SOCKET_PATH`:

  ```ruby
  SOCKET_PATH = ENV.fetch("MOP_SUPERVISOR_SOCKET", Rails.root.join("tmp/sockets/agents_supervisor.sock").to_s).freeze
  ```

- [ ] **Step 4: Green.** Re-run `test/integration/supervisor_v2_test.rb`. Expected: 3 runs / 0 failures.

  Run the full `test/services/agents_supervisor/client_test.rb` to confirm the Phase 2 client tests still pass (they don't exercise the supervisor — they mock the socket — so this should be a no-op).

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.5: supervisor v2 — bounded pool, line-byte cap, bad-parse cap, single-writer-per-connection
  ```

---

## Task 4.6 — `terminal_sessions` migration + `TerminalSession` model + `Sweepable`

- [ ] **Step 1: Migration.**

  ```bash
  bin/rails g migration CreateTerminalSessions
  ```

  ```ruby
  class CreateTerminalSessions < ActiveRecord::Migration[8.1]
    def change
      create_table :terminal_sessions do |t|
        t.references :user,              null: false, foreign_key: true
        t.string  :tmux_session_name,    null: false
        t.integer :cols,                 null: false, default: 120
        t.integer :rows,                 null: false, default: 40
        t.string  :cwd,                  null: false
        t.integer :status,               null: false, default: 0
        t.datetime :last_activity_at,    null: false
        t.timestamps
      end
      add_index :terminal_sessions, :tmux_session_name, unique: true
      add_index :terminal_sessions, [:user_id, :status]
    end
  end
  ```

  `cols/rows/cwd` carry the Phase 1 defaults; `status` enum below.

- [ ] **Step 2: Model.** `app/models/terminal_session.rb`:

  ```ruby
  class TerminalSession < ApplicationRecord
    include Eventable
    include Sweepable  # see Step 3

    belongs_to :user
    enum :status, { starting: 0, live: 1, detached: 2, terminated: 3 }, default: :starting

    validates :tmux_session_name, presence: true, uniqueness: true
    validates :cwd, presence: true

    before_validation :assign_tmux_session_name, on: :create

    scope :reattachable, -> { detached.where("last_activity_at > ?", 1.hour.ago) }

    def attach!
      update!(status: :live, last_activity_at: Time.current)
      track_event :attached
    end

    def detach!
      update!(status: :detached, last_activity_at: Time.current)
      track_event :detached
    end

    def terminate!
      transaction do
        AgentsSupervisor::Client.call("terminal.close", session_id: id)
        update!(status: :terminated, last_activity_at: Time.current)
        track_event :terminated
      end
    end

    private

    def assign_tmux_session_name
      self.tmux_session_name ||= "mop-term-#{SecureRandom.hex(4)}"
    end
  end
  ```

- [ ] **Step 3: `TerminalSession::Sweepable` concern.** `app/models/terminal_session/sweepable.rb`:

  ```ruby
  module TerminalSession::Sweepable
    extend ActiveSupport::Concern

    DETACH_TTL = ENV.fetch("MOP_TERMINAL_TTL_HOURS", "1").to_i.hours

    included do
      scope :sweepable, -> { detached.where("last_activity_at < ?", Time.current - DETACH_TTL) }
    end

    class_methods do
      def sweep!
        sweepable.find_each(&:terminate!).size
      end
    end
  end
  ```

- [ ] **Step 4: Fixtures + tests.** `test/fixtures/terminal_sessions.yml` (minimal); `test/models/terminal_session_test.rb` + `test/models/terminal_session/sweepable_test.rb`:

  - `attach!` transitions `:starting → :live`, tracks `:attached` event.
  - `detach!` from `:live → :detached`.
  - `terminate!` calls `AgentsSupervisor::Client.call("terminal.close", session_id: …)` (stub) and transitions to `:terminated`.
  - Validation: `tmux_session_name` auto-assigned on create; uniqueness enforced.
  - `sweepable` returns only `detached` rows past `DETACH_TTL`.
  - `sweep!` calls `terminate!` per row.

  Run; expected: all green.

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.6: terminal_sessions migration + TerminalSession + Sweepable concern
  ```

---

## Task 4.7 — `Terminal::TmuxManager` + supervisor v2 `terminal.*` RPC methods

The TmuxManager lives **inside the supervisor process** (the Rails web/worker processes never shell out to `tmux` directly — only the supervisor does). `app/services/terminal/tmux_manager.rb` is the in-Rails service object that wraps the supervisor RPC.

- [ ] **Step 1: TmuxManager service in Rails.** `app/services/terminal/tmux_manager.rb`:

  ```ruby
  class Terminal::TmuxManager
    def self.create(terminal_session)
      AgentsSupervisor::Client.call(
        "terminal.create",
        session_id: terminal_session.id,
        cwd:        WorkspacePath.resolve(root: Rails.application.config.x.mop_home, raw: terminal_session.cwd).to_s,
        cols:       terminal_session.cols,
        rows:       terminal_session.rows
      )
    end

    def self.send_keys(terminal_session, data)
      AgentsSupervisor::Client.call("terminal.input", session_id: terminal_session.id, data:)
    end

    def self.resize(terminal_session, cols, rows)
      AgentsSupervisor::Client.call("terminal.resize", session_id: terminal_session.id, cols:, rows:)
    end

    def self.close(terminal_session)
      AgentsSupervisor::Client.call("terminal.close", session_id: terminal_session.id)
    end
  end
  ```

  Note the `WorkspacePath.resolve` call — defence-in-depth path traversal guard before passing `cwd` to tmux (see hardening gate item #3).

- [ ] **Step 2: `AgentsSupervisor::Client.call` RPC wrapper.** Today the client only handles **notification** traffic (the `consume` loop reads notifications and never sends requests). Phase 4 adds a synchronous request path. Edit `app/services/agents_supervisor/client.rb`:

  ```ruby
  def self.call(method, params = {}, timeout: 5)
    socket = UNIXSocket.open(SOCKET_PATH.to_s)
    id     = SecureRandom.hex(4)
    request = { jsonrpc: "2.0", id:, method:, params: params }.to_json + "\n"
    socket.write(request)
    response = Timeout.timeout(timeout) { socket.gets }
    parsed   = JSON.parse(response)
    raise SupervisorError, parsed.dig("error", "message") if parsed["error"]
    parsed["result"]
  ensure
    socket&.close
  end
  ```

  Add `class SupervisorError < StandardError; end` at module top.

  (This opens a fresh socket per call. Fine for low-volume RPC. The notification-subscription socket from Phase 2 stays separate; this fits the supervisor v2 design where each connection has its own writer thread.)

- [ ] **Step 3: Tmux-side handlers in `bin/agents_supervisor`.** Add a `TmuxBridge` PORO inside the supervisor:

  ```ruby
  class TmuxBridge
    def initialize = @pumps = Concurrent::Map.new

    def open(session_id:, cwd:, cols:, rows:)
      name = "mop-term-#{session_id}"
      run!("tmux", "new-session", "-d", "-s", name, "-x", cols.to_s, "-y", rows.to_s, "-c", cwd)
      fifo = Rails.root.join("tmp/sockets/term-#{session_id}.fifo")
      File.mkfifo(fifo) unless fifo.exist?
      run!("tmux", "pipe-pane", "-t", name, "-o", "cat >> #{fifo}")
      @pumps[session_id] = Thread.new { stream_pump(session_id, fifo) }
      { tmux_session_name: name }
    end

    def input(session_id:, data:)
      run!("tmux", "send-keys", "-t", "mop-term-#{session_id}", "-l", data)  # -l = literal, no key parsing
      {}
    end

    def resize(session_id:, cols:, rows:)
      run!("tmux", "resize-window", "-t", "mop-term-#{session_id}", "-x", cols.to_s, "-y", rows.to_s)
      {}
    end

    def close(session_id:)
      @pumps.delete(session_id)&.kill
      run!("tmux", "kill-session", "-t", "mop-term-#{session_id}")
      {}
    rescue => e
      Rails.logger.warn("[supervisor] tmux kill failed: #{e.message}")
      {}
    end

    private

    def run!(*argv)
      # ARRAY form — never string-interpolated. cwd already WorkspacePath-resolved by Rails.
      out, status = Open3.capture2e(*argv)
      raise "tmux command failed: #{argv.inspect}\n#{out}" unless status.success?
      out
    end

    def stream_pump(session_id, fifo)
      File.open(fifo, "r") do |f|
        f.each_line do |chunk|
          ActionCable.server.broadcast("terminal_#{session_id}", { type: "chunk", data: chunk })
        end
      end
    rescue => e
      Rails.logger.warn("[supervisor] stream_pump exited: #{e.message}")
    end
  end
  ```

  Wire into `handle_request`:

  ```ruby
  tmux = TmuxBridge.new
  handle_request = ->(line) {
    req    = JSON.parse(line)
    method = req["method"]
    params = (req["params"] || {}).symbolize_keys
    result =
      case method
      when "health.ping" then { pong: true, pid: Process.pid }
      when "terminal.create" then tmux.open(**params)
      when "terminal.input"  then tmux.input(**params)
      when "terminal.resize" then tmux.resize(**params)
      when "terminal.close"  then tmux.close(**params)
      else
        return { jsonrpc: "2.0", id: req["id"], error: { code: -32601, message: "method not found: #{method}" } }.to_json
      end
    { jsonrpc: "2.0", id: req["id"], result: result }.to_json
  }
  ```

  **Security note** (also in the hardening gate): every `run!` call uses the array form of `Open3.capture2e`. The `cwd` argument is `WorkspacePath.resolve`d Rails-side before it reaches the supervisor, so a malicious `cwd` can't escape `${MOP_HOME}`. The `pipe-pane "cat >> #{fifo}"` string is the one shell-interpolated bit; `fifo` is a server-generated `Rails.root.join("tmp/sockets/term-#{session_id}.fifo")` (Integer-keyed), so it's not user-influenceable.

- [ ] **Step 4: Tests.** Two layers:

  1. `test/services/terminal/tmux_manager_test.rb` — mocks `AgentsSupervisor::Client.call`, asserts each method calls with the expected method-name + params. Includes the `WorkspacePath.resolve` traversal-probe test (`cwd: "../../../etc"` → `WorkspacePath::EscapeAttempt`).
  2. `test/integration/supervisor_v2_test.rb` — extend with `terminal.create` + `terminal.input` against a real tmux (skip with `omit "tmux not installed" unless system('which tmux')` for CI environments without tmux).

  Run; expected: green.

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.7: Terminal::TmuxManager + supervisor v2 terminal.* RPC methods (array-form Open3, WorkspacePath.resolve on cwd)
  ```

---

## Task 4.8 — `TerminalChannel` + `TerminalsController` + xterm.js + `terminal_controller.js`

- [ ] **Step 1: Routes.** Edit `config/routes.rb`:

  ```ruby
  resources :terminals, only: %i[index show create destroy]
  ```

  No custom action routes (Talento HQ pattern). Input/resize go through the channel.

- [ ] **Step 2: Controller.** `app/controllers/terminals_controller.rb`:

  ```ruby
  class TerminalsController < ApplicationController
    before_action :set_terminal_session, only: %i[show destroy]

    def index
      @terminal_sessions = current_user.terminal_sessions.where.not(status: :terminated).order(updated_at: :desc)
    end

    def create
      @terminal_session = current_user.terminal_sessions.create!(
        cwd:  params[:cwd].presence || Rails.application.config.x.mop_home,
        cols: 120,
        rows: 40,
        last_activity_at: Time.current
      )
      Terminal::TmuxManager.create(@terminal_session)
      @terminal_session.attach!
      redirect_to terminal_path(@terminal_session)
    end

    def show; end

    def destroy
      @terminal_session.terminate!
      redirect_to terminals_path, notice: "Terminal closed."
    end

    private

    def set_terminal_session
      @terminal_session = current_user.terminal_sessions.find(params[:id])
    end
  end
  ```

  Note `current_user.terminal_sessions.find(params[:id])` — multi-tenancy. A user attaching to another user's terminal raises `RecordNotFound` → 404. **Cross-tenancy regression test required** — see hardening gate item #11.

- [ ] **Step 3: Channel.** `app/channels/terminal_channel.rb`:

  ```ruby
  class TerminalChannel < ApplicationCable::Channel
    def subscribed
      terminal_session = current_user.terminal_sessions.find_by(id: params[:terminal_session_id])
      if terminal_session
        stream_for terminal_session  # streams from "terminal_<id>" namespace
      else
        Rails.logger.info("[TerminalChannel] reject: user=#{current_user.id} terminal_session_id=#{params[:terminal_session_id]}")
        reject
      end
    end

    def receive(data)
      terminal_session = current_user.terminal_sessions.find(params[:terminal_session_id])
      case data["type"]
      when "input"  then Terminal::TmuxManager.send_keys(terminal_session, data["data"])
      when "resize" then Terminal::TmuxManager.resize(terminal_session, data["cols"].to_i, data["rows"].to_i)
      end
    end

    def unsubscribed
      terminal_session = current_user.terminal_sessions.find_by(id: params[:terminal_session_id])
      terminal_session&.detach!
    end
  end
  ```

  The supervisor's stream pump already broadcasts to `"terminal_<id>"`; the channel's `stream_for terminal_session` subscribes to the same namespace.

- [ ] **Step 4: Importmap pins.**

  ```bash
  bin/importmap pin xterm @xterm/addon-fit @xterm/addon-search @xterm/addon-web-links
  ```

  Verify entries land in `config/importmap.rb` and that `vendor/javascript/` contains the pinned files (or they're served from the CDN per `pin` strategy).

- [ ] **Step 5: Stimulus controller.** `app/javascript/controllers/terminal_controller.js`:

  ```js
  import { Controller } from "@hotwired/stimulus"
  import { Terminal } from "xterm"
  import { FitAddon } from "@xterm/addon-fit"
  import consumer from "channels/consumer"

  export default class extends Controller {
    static values = { sessionId: Number }

    connect() {
      this.term = new Terminal({ convertEol: true, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" })
      this.fit  = new FitAddon()
      this.term.loadAddon(this.fit)
      this.term.open(this.element)
      this.fit.fit()

      this.subscription = consumer.subscriptions.create(
        { channel: "TerminalChannel", terminal_session_id: this.sessionIdValue },
        {
          received: (event) => {
            if (event.type === "chunk") this.term.write(event.data)
          }
        }
      )

      this.term.onData((data) => this.subscription.perform("receive", { type: "input", data }))
      window.addEventListener("resize", this.onResize)
    }

    disconnect() {
      this.subscription?.unsubscribe()
      window.removeEventListener("resize", this.onResize)
    }

    onResize = () => {
      this.fit.fit()
      this.subscription?.perform("receive", { type: "resize", cols: this.term.cols, rows: this.term.rows })
    }
  }
  ```

- [ ] **Step 6: Views.** `app/views/terminals/index.html.erb`, `app/views/terminals/show.html.erb`. Show:

  ```erb
  <div data-controller="terminal" data-terminal-session-id-value="<%= @terminal_session.id %>"
       class="terminal-host" style="height: 70vh"></div>
  ```

  Add minimal CSS in `app/assets/stylesheets/components/terminal.css` for `.terminal-host` (background, padding). Follow the modern-css skill's OKLCH-token approach.

- [ ] **Step 7: Test surface.**
  - `test/controllers/terminals_controller_test.rb` — create/show/destroy + multi-tenancy (user B can't `GET /terminals/<user A's id>`).
  - `test/channels/terminal_channel_test.rb` — subscribe with valid session → `streams_for terminal_session`; subscribe with mismatched user → rejected.
  - `test/system/terminal_test.rb` — Capybara: visit `/terminals/new`, fill cwd, see xterm canvas, send `echo hi\n`, assert output appears. Skip on CI without tmux.

- [ ] **Step 8: Commit.**

  ```
  Phase 4 Task 4.8: TerminalChannel + TerminalsController + xterm.js + terminal_controller.js
  ```

---

## Task 4.9 — `Terminal::SweepJob` recurring + reattachment scrollback

- [ ] **Step 1: Sweep job.** `app/jobs/terminal/sweep_job.rb`:

  ```ruby
  class Terminal::SweepJob < ApplicationJob
    queue_as :default
    def perform = TerminalSession.sweep!
  end
  ```

  Recurring config in `config/recurring.yml`:

  ```yaml
  sweep_terminals:
    class: Terminal::SweepJob
    schedule: every 15 minutes
  ```

- [ ] **Step 2: Reattachment scrollback.** On `TerminalChannel#subscribed`, after `stream_for`, send the last N lines of pane contents:

  ```ruby
  def subscribed
    terminal_session = current_user.terminal_sessions.find_by(id: params[:terminal_session_id])
    return reject unless terminal_session

    stream_for terminal_session
    terminal_session.attach!
    scrollback = AgentsSupervisor::Client.call("terminal.capture", session_id: terminal_session.id, lines: 500)
    transmit({ type: "scrollback", data: scrollback["text"] })
  end
  ```

  Supervisor handler: `tmux.capture_pane(session_id:, lines:)` → `Open3.capture2e("tmux", "capture-pane", "-p", "-t", "mop-term-#{session_id}", "-S", "-#{lines}")`.

  Stimulus controller handles `{ type: "scrollback" }` events by clearing the terminal and `term.write(data)`.

- [ ] **Step 3: Tests.** `test/jobs/terminal/sweep_job_test.rb` mirrors the session sweep test. `test/channels/terminal_channel_test.rb` adds: subscribing to a `detached` session transitions it back to `:live` and transmits a `scrollback` event.

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.9: Terminal::SweepJob + reattachment scrollback via tmux capture-pane
  ```

---

## Task 4.10 — `mcp_servers` + `mcp_tools` migrations + models + concerns

- [ ] **Step 1: Migrations.**

  ```bash
  bin/rails g migration CreateMcpServers
  bin/rails g migration CreateMcpTools
  ```

  `mcp_servers`:

  ```ruby
  class CreateMcpServers < ActiveRecord::Migration[8.1]
    def change
      create_table :mcp_servers do |t|
        t.references :user,            null: false, foreign_key: true
        t.string  :slug,               null: false
        t.string  :name,               null: false
        t.integer :transport_type,     null: false, default: 0  # 0=http, 1=sse, 2=stdio
        t.string  :url
        t.string  :command_template               # stdio only
        t.text    :env_payload                     # encrypted (Rails 8 native)
        t.integer :auth_type,          null: false, default: 0  # 0=none, 1=bearer, 2=basic
        t.text    :auth_payload                    # encrypted
        t.integer :tool_mode,          null: false, default: 0  # 0=all, 1=include, 2=exclude
        t.json    :tool_list                       # [] | ["search","fetch"]
        t.integer :status,             null: false, default: 0  # 0=unknown, 1=reachable, 2=error, 3=disabled
        t.string  :last_error
        t.datetime :last_checked_at
        t.timestamps
      end
      add_index :mcp_servers, [:user_id, :slug], unique: true
    end
  end
  ```

  `mcp_tools`:

  ```ruby
  class CreateMcpTools < ActiveRecord::Migration[8.1]
    def change
      create_table :mcp_tools do |t|
        t.references :mcp_server, null: false, foreign_key: true
        t.string :name,           null: false
        t.text   :description
        t.json   :input_schema,   null: false, default: {}
        t.datetime :discovered_at
        t.timestamps
      end
      add_index :mcp_tools, [:mcp_server_id, :name], unique: true
      add_index :mcp_tools, :name  # for Message::Streamable#infer_source lookup
    end
  end
  ```

- [ ] **Step 2: `McpServer` model + concerns.**

  `app/models/mcp_server.rb`:

  ```ruby
  class McpServer < ApplicationRecord
    include Eventable
    include Enableable
    include Discoverable

    belongs_to :user
    has_many :tools, class_name: "McpTool", dependent: :destroy

    encrypts :env_payload, :auth_payload

    enum :transport_type, { http: 0, sse: 1, stdio: 2 }
    enum :auth_type,      { none: 0, bearer: 1, basic: 2 }
    enum :tool_mode,      { all: 0, include_list: 1, exclude_list: 2 }
    enum :status,         { unknown: 0, reachable: 1, error: 2, disabled: 3 }

    validates :slug, presence: true, uniqueness: { scope: :user_id }
    validates :name, :transport_type, presence: true
    validates :url,              presence: true, if: -> { http? || sse? }
    validates :command_template, presence: true, if: :stdio?

    def env
      JSON.parse(env_payload || "{}")
    end
  end
  ```

  `app/models/mcp_server/enableable.rb` — **decision: bool/status-enum form, not a child table.** Rationale: workflows.md:156 says "pick at Phase 4 — bool flag or child table"; single-user installs don't need the non-repudiation audit a child table buys, and the `:disabled` value is already a first-class member of the `status` enum.

  ```ruby
  module McpServer::Enableable
    extend ActiveSupport::Concern

    def enable!
      return if reachable?
      transaction do
        update!(status: :unknown)
        track_event :enabled
      end
      Mcp::DiscoveryJob.perform_later(id)
    end

    def disable!
      transaction do
        update!(status: :disabled)
        track_event :disabled
      end
    end
  end
  ```

  `app/models/mcp_server/discoverable.rb`:

  ```ruby
  module McpServer::Discoverable
    extend ActiveSupport::Concern

    def discover_tools!
      client = Mcp::HttpClient.new(self) if http? || sse?
      raise "stdio discovery lands in Phase 4.5" if stdio?  # see Open items
      definitions = client.list_tools  # [{ name:, description:, input_schema: }, ...]
      transaction do
        tools.delete_all
        definitions.each { |d| tools.create!(d.merge(discovered_at: Time.current)) }
        update!(status: :reachable, last_checked_at: Time.current, last_error: nil)
        track_event :tools_discovered, particulars: { count: definitions.size }
      end
    rescue => e
      update!(status: :error, last_error: e.message.first(255), last_checked_at: Time.current)
      track_event :discovery_failed, particulars: { error: e.message.first(255) }
      raise
    end

    def discover_tools_later
      Mcp::DiscoveryJob.perform_later(id)
    end
  end
  ```

- [ ] **Step 3: `McpTool` model.** `app/models/mcp_tool.rb`:

  ```ruby
  class McpTool < ApplicationRecord
    belongs_to :mcp_server

    scope :exposed, -> { joins(:mcp_server).merge(McpServer.reachable) }

    def invoke(input:, user:)
      raise "tenant violation" unless mcp_server.user_id == user.id
      client = Mcp::HttpClient.new(mcp_server)
      output = client.call_tool(name, input)
      Tool::Result.success(output)
    rescue => e
      Tool::Result.failure("mcp_tool '#{name}' failed: #{e.message.first(255)}")
    end

    def self.lookup(name)
      exposed.find_by(name: name)
    end
  end
  ```

- [ ] **Step 4: Tests.**
  - `test/models/mcp_server_test.rb` — validations, enum members, `enable!`/`disable!` transitions + event tracking.
  - `test/models/mcp_server/discoverable_test.rb` — stub `Mcp::HttpClient#list_tools`; assert transaction wraps + tools row created + status flips to `:reachable`. Failure path → `:error` + `last_error` stored.
  - `test/models/mcp_tool_test.rb` — `invoke` returns `Tool::Result.success` on happy path, `Tool::Result.failure` on raise; tenant guard raises if user mismatches.

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.10: mcp_servers + mcp_tools schema + McpServer (Enableable + Discoverable) + McpTool
  ```

---

## Task 4.11 — `Mcp::HttpClient` + `Mcp::DiscoveryJob`

- [ ] **Step 1: HTTP client.** `app/services/mcp/http_client.rb`:

  ```ruby
  class Mcp::HttpClient
    def initialize(server)
      @server = server
      Mcp::OutboundGuard.allowed!(server.url)
      @conn = Faraday.new(url: server.url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.adapter Faraday.default_adapter
        f.headers["User-Agent"] = "master-of-puppets/#{Rails.application.config.x.version}"
        case server.auth_type
        when "bearer" then f.request :authorization, "Bearer", JSON.parse(server.auth_payload || "{}")["token"]
        when "basic"
          creds = JSON.parse(server.auth_payload || "{}")
          f.request :authorization, :basic, creds["username"], creds["password"]
        end
      end
    end

    def list_tools
      json_rpc("tools/list").fetch("tools", []).map do |t|
        { name: t.fetch("name"), description: t["description"], input_schema: t["inputSchema"] || {} }
      end
    end

    def call_tool(name, input)
      json_rpc("tools/call", name:, arguments: input)
    end

    def ping
      json_rpc("ping")
      true
    end

    private

    def json_rpc(method, params = {})
      body = { jsonrpc: "2.0", id: SecureRandom.hex(4), method:, params: }
      response = @conn.post("", body)
      raise "MCP #{method} failed: #{response.status}" unless response.success?
      raise "MCP #{method} error: #{response.body['error']}" if response.body["error"]
      response.body["result"]
    end
  end
  ```

  **SSRF guard** (hardening gate item #10) — new PORO `app/services/mcp/outbound_guard.rb`:

  ```ruby
  class Mcp::OutboundGuard
    DENYLIST = %w[169.254.169.254 169.254.170.2].freeze
    PRIVATE  = [IPAddr.new("10.0.0.0/8"), IPAddr.new("172.16.0.0/12"), IPAddr.new("192.168.0.0/16"), IPAddr.new("127.0.0.0/8")]

    def self.allowed!(url)
      uri  = URI.parse(url)
      host = uri.host
      addr = Resolv.getaddress(host)
      raise "denied: cloud metadata IP" if DENYLIST.include?(addr)
      if PRIVATE.any? { |range| range.include?(IPAddr.new(addr)) } && ENV["MOP_MCP_ALLOW_PRIVATE"] != "1"
        raise "denied: private range — set MOP_MCP_ALLOW_PRIVATE=1 to override"
      end
    end
  end
  ```

  Mirrors the spirit of `WorkspacePath` for outbound HTTP.

- [ ] **Step 2: Discovery job.** `app/jobs/mcp/discovery_job.rb`:

  ```ruby
  class Mcp::DiscoveryJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: ->(id) { "mcp-discover:#{id}" }, on_conflict: :discard

    def perform(id) = McpServer.find(id).discover_tools!
  end
  ```

- [ ] **Step 3: Tests.**
  - `test/services/mcp/http_client_test.rb` — stub Faraday adapter via `Faraday::Adapter::Test`; assert `list_tools` returns the parsed tool list, bearer-auth header injected, error response raises.
  - `test/services/mcp/outbound_guard_test.rb` — `169.254.169.254` blocked, `10.0.0.0/8` blocked by default, allowed under env flag.
  - `test/jobs/mcp/discovery_job_test.rb` — stubs `McpServer#discover_tools!`, asserts perform invokes it.

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.11: Mcp::HttpClient (JSON-RPC over HTTP) + outbound SSRF guard + Mcp::DiscoveryJob
  ```

---

## Task 4.12 — `Tool::Mcp` sibling registry + dispatch wiring

Decision: keep `Tool::Internal` and `Tool::Mcp` as **sibling registries**. `Tool::Internal.lookup` does not delegate to MCP. `Message::Streamable#available_tools` concatenates both.

- [ ] **Step 1: `Tool::Mcp` PORO.** `app/models/tool/mcp.rb`:

  ```ruby
  module Tool::Mcp
    def self.all_definitions(user:)
      McpTool.exposed.where(mcp_server: { user_id: user.id }).map do |t|
        { name: t.name, description: t.description, input_schema: t.input_schema }
      end
    end

    def self.lookup(name) = McpTool.lookup(name)

    def self.invoke(name:, input:, user:)
      tool = lookup(name)
      return Tool::Result.failure("unknown mcp tool: #{name}") unless tool
      tool.invoke(input:, user:)
    end
  end
  ```

- [ ] **Step 2: Restore the `:mcp` arm in `Message::Streamable#infer_source`.** Edit `app/models/message/streamable.rb` (currently lines 107–110):

  ```ruby
  def infer_source(name)
    return :internal if Tool::Internal.lookup(name)
    return :mcp      if Tool::Mcp.lookup(name)
    :unknown
  end
  ```

  And `available_tools`:

  ```ruby
  def available_tools
    defs = Tool::Internal.all_definitions
    defs = defs.reject { |d| d[:name] == "run_shell" } unless chat_session.user.admin?
    defs + Tool::Mcp.all_definitions(user: chat_session.user)
  end
  ```

- [ ] **Step 3: Replace the placeholder arm in `ToolCall::Executable`.** Edit `app/models/tool_call/executable.rb` (currently lines 24–33):

  ```ruby
  result =
    case source.to_sym
    when :internal
      Tool::Internal.invoke(name: name, input: input.to_h, user: message.chat_session.user)
    when :mcp
      Tool::Mcp.invoke(name: name, input: input.to_h, user: message.chat_session.user)
    when :skill
      Tool::Result.failure("skill-as-tool lands in Phase 6")
    when :unknown
      Tool::Result.failure("unknown tool: #{name}")
    else
      raise UnsupportedSource, source
    end
  ```

  (`:skill` source stays a placeholder until Phase 6's agent-profile work — that's correct.)

- [ ] **Step 4: Tests.**
  - `test/models/tool/mcp_test.rb` — `lookup` returns the right tool; `invoke` for an unknown name returns `Tool::Result.failure("unknown mcp tool: ...")`; `all_definitions(user:)` scopes to that user's servers.
  - `test/models/message/streamable_test.rb` — extend `infer_source` test to cover the `:mcp` arm with an `McpTool` fixture; assert `available_tools` includes the MCP definitions; assert `available_tools` still excludes `run_shell` for non-admins.
  - `test/models/tool_call/executable_test.rb` — add: a `:mcp` source with a real `McpTool` fixture invokes `Tool::Mcp.invoke` (stub the HTTP client) and writes the output to `output_payload`.

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.12: Tool::Mcp sibling registry + restore :mcp arms in Message::Streamable + ToolCall::Executable
  ```

---

## Task 4.13 — `McpServersController` + tests sub-resource + views

- [ ] **Step 1: Routes.** `config/routes.rb`:

  ```ruby
  resources :mcp_servers do
    scope module: :mcp_servers do
      resource :test,      only: %i[create]
      resource :discovery, only: %i[create]
    end
  end
  ```

  No custom-action routes — connectivity-check is a nested singular `test` resource (Talento HQ convention).

- [ ] **Step 2: Controllers.** `app/controllers/mcp_servers_controller.rb` (RESTful: index/show/new/create/edit/update/destroy), `app/controllers/mcp_servers/tests_controller.rb#create` calls `Mcp::HttpClient#ping`, `mcp_servers/discoveries_controller.rb#create` enqueues `Mcp::DiscoveryJob`. Admin-gate the index/create/update/destroy actions for now (single-user install policy).

- [ ] **Step 3: Views.** `mcp_servers/{index,show,new,edit}.html.erb` + `mcp_servers/tests/create.turbo_stream.erb` for the inline status badge. Reuse Phase 3's `.badge` styles.

- [ ] **Step 4: Tests.** Controller tests + a `test/system/mcp_test.rb` system test that creates a stub MCP server (WebMock against an HTTP URL), runs discovery, and clicks through to see the discovered tools.

- [ ] **Step 5: Commit.**

  ```
  Phase 4 Task 4.13: McpServersController + nested tests/discoveries resources + views
  ```

---

## Task 4.14 — CSP initializer activation (§ 15.7)

`config/initializers/content_security_policy.rb` is currently the stock Rails commented stub. Workflows.md § 15.7 spelled out the policy in Phase 1, but it was never applied. Monaco (Phase 4.5) and `esm.sh` need this active.

- [ ] **Step 1: Replace the stub.**

  ```ruby
  Rails.application.config.content_security_policy do |policy|
    policy.default_src :self
    policy.style_src   :self, :unsafe_inline                # xterm.js + monaco inline styles
    policy.script_src  :self, "https://esm.sh"              # Monaco CDN (4.5)
    policy.worker_src  :self, :blob                         # Monaco workers
    policy.connect_src :self, "wss:", "ws:"
    policy.img_src     :self, :data, :blob
    policy.media_src   :self, :data
    policy.font_src    :self, :data
  end

  Rails.application.config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  Rails.application.config.content_security_policy_nonce_directives = %w(script-src)
  Rails.application.config.content_security_policy_report_only = false
  ```

- [ ] **Step 2: Test.** `test/integration/csp_test.rb` (or extend existing security boot-check test):

  ```ruby
  test "GET / sets the §15.7 CSP" do
    sign_in_as users(:alice)
    get root_path
    csp = response.headers["Content-Security-Policy"]
    assert_match(/default-src 'self'/, csp)
    assert_match(%r{script-src .*'self'.*https://esm\.sh}, csp)
    assert_match(/worker-src .*'self'.*blob:/, csp)
  end
  ```

- [ ] **Step 3: Brakeman.** Expect Brakeman to **not** flag the new CSP (it flags missing CSP; activating one is the fix). Verify with `bin/bundle exec brakeman -A`.

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.14: activate §15.7 Content-Security-Policy initializer
  ```

---

## Task 4.15 — `run_shell` via supervisor (rlimits + uid drop on Linux)

Phase 3 stop-gap at `app/models/tool/internal/run_shell.rb`: prod-off env flag + secret env scrub + PGID kill. Phase 4 routes through the supervisor's new `shell.run` RPC so rlimits + (on Linux) uid drop become available. macOS dev keeps the env-scrub + PGID-kill posture — see Open items.

- [ ] **Step 1: Supervisor `shell.run` handler.** Add to `bin/agents_supervisor`:

  ```ruby
  class ShellBridge
    SCRUBBED = %w[DATABASE_URL RAILS_MASTER_KEY ANTHROPIC_API_KEY OPENAI_API_KEY].freeze
    RLIMITS = {
      rlimit_cpu:    [30, 30],
      rlimit_as:     [512 * 1024 * 1024, 512 * 1024 * 1024],  # 512MB virt
      rlimit_nofile: [64, 64]
    }

    def run(command:, cwd:, timeout: 30)
      env  = SCRUBBED.zip([nil] * SCRUBBED.size).to_h
      opts = { chdir: cwd, pgroup: true, **RLIMITS }
      # uid drop only if supervisor itself is privileged AND opt-in marker exists.
      opts[:uid] = Process.uid - 1 if Process.uid.zero? && File.exist?("/etc/master_of_puppets/uid")
      run_with_timeout(env, command, opts, timeout)
    end

    private

    def run_with_timeout(env, command, opts, timeout)
      pid = Process.spawn(env, command, opts)
      status = nil
      Timeout.timeout(timeout) { _, status = Process.waitpid2(pid) }
      { stdout: "", stderr: "", exit_code: status.exitstatus, pid: pid }
    rescue Timeout::Error
      kill_pgroup!(pid)
      { stdout: "", stderr: "", exit_code: -1, timed_out: true }
    end
    # ...full impl mirrors current run_shell.rb, with the Open3.popen3 → Process.spawn switch
    # so RLIMITS apply via the rlimit_* kwargs. Capture stdout/stderr via redirected pipes.
  end
  ```

  Note: uid drop only fires if the supervisor itself was started as root **and** an opt-in marker file exists. We don't actually run as root in dev; document the gap.

- [ ] **Step 2: Rails-side `Tool::Internal::RunShell` calls supervisor.** Edit `app/models/tool/internal/run_shell.rb`:

  ```ruby
  def self.invoke(input:, user:)
    return Tool::Result.failure("run_shell is admin-only") unless user&.admin?
    command = input.fetch("command")
    return Tool::Result.failure("empty command") if command.blank?

    cwd = WorkspacePath.resolve(root: Rails.application.config.x.mop_home, raw: input["cwd"] || ".").to_s
    result = AgentsSupervisor::Client.call("shell.run", command:, cwd:, timeout: TIMEOUT_SECONDS)
    if result["timed_out"]
      Tool::Result.failure("timeout after #{TIMEOUT_SECONDS}s")
    elsif result["exit_code"].to_i.zero?
      Tool::Result.success(result["stdout"].to_s.byteslice(0, MAX_OUTPUT_BYTES))
    else
      Tool::Result.failure("exit #{result['exit_code']}\n#{result['stderr'].to_s.byteslice(0, MAX_OUTPUT_BYTES)}")
    end
  end
  ```

  The phase-3 in-process codepath stays as `app/models/tool/internal/run_shell/in_process.rb` for the `MOP_RUN_SHELL_FORCE_IN_PROCESS=1` test/integration convenience.

- [ ] **Step 3: Tests.**
  - `test/models/tool/internal/run_shell_test.rb` — extend with: supervisor RPC stubbed (returns a happy-path payload + a timeout payload + a non-zero-exit payload), assertions on the three result branches.
  - `test/integration/supervisor_v2_test.rb` — extend: `shell.run` with `ls /` returns `exit_code: 0`, `stdout` non-empty.

- [ ] **Step 4: Commit.**

  ```
  Phase 4 Task 4.15: run_shell via supervisor shell.run (rlimits + env scrub + pgroup + timeout)
  ```

---

## Task 4.16 — Phase 4 exit criteria + verification

- [ ] **Configure an HTTP MCP server (context7) and call its tools from chat.** End-to-end: `/mcp_servers/new`, save, click "Test" → status `:reachable`; click "Discover tools" → `mcp_tools` rows materialize; in chat, the LLM calls a discovered tool → `ToolCall` row with `source: :mcp` → `Tool::Result.success`. Covered by `test/system/mcp_test.rb` + the new branch in `test/models/tool_call/executable_test.rb`.
- [ ] **Open a terminal, run commands, disconnect, reattach within TTL with scrollback intact.** Covered by `test/system/terminal_test.rb` (skipped on CI without tmux) + `test/channels/terminal_channel_test.rb` for the scrollback transmit.
- [ ] **Expired web sessions pruned hourly; idle session past `expires_at` redirects to sign-in.** Covered by `test/controllers/application_controller_test.rb` (expired → redirect) + `test/jobs/session/sweep_job_test.rb`.
- [ ] **`run_shell` routes through the supervisor.** Covered by `test/models/tool/internal/run_shell_test.rb` extension + `test/integration/supervisor_v2_test.rb`.
- [ ] **Worker-0 boot replay collapses N×-per-worker fan-out to one.** Covered by `test/initializers/boot_replay_test.rb`.
- [ ] **CSP active.** Covered by `test/integration/csp_test.rb`.
- [ ] **All tests pass:**

  ```bash
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```

  Expected: tests green; brakeman count = Phase 3 baseline + 0 new (the new code paths are either WorkspacePath-resolved or pure RPC, not direct File I/O). Bundler-audit: 0 vulnerabilities.

- [ ] **Tag `phase-4`.** `git tag phase-4` after the hardening gate closes.

---

## Phase 4 hardening gate (must-fix before declaring Phase 4 done)

These are the items a future Phase 4 review will flag. Mirror Phase 3's Task 3.15 structure: tick each before the `phase-4` tag.

- [ ] **H1 — `Terminal::TmuxManager` uses array-form `Open3` for every tmux call.** No string interpolation of user-influenceable input into shell strings. A `cwd` like `; rm -rf /` cannot create files. Test: `test/services/terminal/tmux_manager_test.rb#test_cwd_with_shell_metachars_does_not_execute_them`.

- [ ] **H2 — MCP child process leak on supervisor SIGKILL is documented + drained on next boot.** When supervisor v2 receives SIGTERM it kills all tmux + MCP children cleanly. SIGKILL leaks orphans. Mitigation: on boot, the supervisor scans `pgrep -f mop-term-` and `pgrep -f mop-mcp-` and kills strays. Test: integration test that pre-spawns a dummy tmux session named `mop-term-orphan` then asserts a supervisor boot kills it. (4.5 candidate if scope tight — document the gap explicitly.)

- [ ] **H3 — `terminal.create cwd` passes through `WorkspacePath.resolve` before reaching tmux.** Defence-in-depth path-traversal guard. Test: `cwd: "../../../etc"` → `WorkspacePath::EscapeAttempt` raised in `Terminal::TmuxManager.create` before any supervisor call.

- [ ] **H4 — Encrypted columns key rotation works.** `bin/rails db:encryption:rotate` against `mcp_servers.{env_payload,auth_payload}` + `provider_configs.api_key`. Document the operator runbook (one line in `README.md` or `docs/operations.md`).

- [ ] **H5 — `TerminalChannel.broadcast_to` caps chunk size + rate-limits.** `MAX_TERMINAL_CHUNK = 64 * 1024`. If the stream pump reads more than that, slice into multiple broadcasts. Coalesce >200 broadcasts/sec/channel by buffering for 50ms. Test: a `yes` flood doesn't exhaust the cable queue. (Possibly out of reach in a system test; unit test the pump rate limiter.)

- [ ] **H6 — MCP child memory ceiling.** When stdio bridge lands (4.5), each MCP child gets a 1 GB RSS ceiling sampled every 30s, hard-killed on breach. For Phase 4 HTTP-only, surface as a `TODO(phase-4.5)`.

- [ ] **H7 — Importmap CDN supply chain (Monaco).** If Monaco lands inline in Phase 4 instead of slipping to 4.5: pin an exact version (`monaco-editor@0.52.0`, not `^0.52`), add SRI hash if importmap supports it (Rails 8 `pin … integrity:`), document the supply-chain risk in `docs/operations.md`. (4.5 candidate.)

- [ ] **H8 — JSON-RPC line buffer DoS pre-`MAX_RPC_LINE_BYTES`.** Verify Task 4.5's integration test exercises a 65 KB-on-a-single-line probe and that the connection closes before allocations balloon. Spot-check with `ulimit -v 512000 && bin/agents_supervisor` + a probe client.

- [ ] **H9 — `Session::SweepJob` reaping with clock skew.** `Session::Sweepable::CLOCK_SKEW_MARGIN = 60.seconds` already added (Task 4.1 Step 2). Test: a session expiring 30s ago is NOT swept; expiring 90s ago IS swept.

- [ ] **H10 — `Mcp::HttpClient` SSRF.** `Mcp::OutboundGuard.allowed!(url)` blocks `169.254.169.254` + RFC1918 ranges by default. Test: creating an `McpServer` with `url: http://10.0.0.5` fails validation unless `MOP_MCP_ALLOW_PRIVATE=1`. Local-network exemption parallels workflows.md § 15.3.

- [ ] **H11 — Cross-tenancy on `TerminalChannel` + `TerminalsController` + MCP.** User B subscribing to user A's `terminal_session_id` is rejected; `GET /terminals/<a-id>` as user B returns 404; `McpTool#invoke` raises if `user.id != mcp_server.user_id`. Cross-tenancy assertions follow the Phase 1 pattern in `test/controllers/concerns/cross_tenancy_assertions.rb` (workflows.md:2563).

- [ ] **H12 — Supervisor v2 graceful shutdown drains in-flight RPCs.** `TRAP("TERM")` → close accept loop → `dispatcher.shutdown` → `dispatcher.wait_for_termination(5)` → kill all tmux/MCP children → unlink socket → `exit 0`. Test: send TERM to a supervisor with 3 in-flight `terminal.input` calls; assert all 3 responses arrive before the process exits.

---

## Task 4.17 — Post-review fix-ups (Phase 4 batch 2) — placeholder

After the hardening gate closes and `phase-4` is tagged, schedule a full code review (run the same 4-parallel-agent cross-check pattern Phase 3 used for Task 3.16). The likely surface (predicted, refine after review):

- Bounded thread-pool sizing on the supervisor proven adequate under load.
- TmuxBridge stream pump backpressure when the channel queue is saturated.
- `Mcp::HttpClient` retry strategy (today: fail loud; review may want exponential backoff for `:reachable` health checks).
- The `TerminalChannel` `unsubscribed` callback can mis-fire on transient disconnects; ensure `detach!` is idempotent and doesn't double-track events.
- `Session::Sweepable#touch_and_maybe_rotate!` runs on every authenticated request — measure its hot-path cost (it does one `UPDATE` row-level write); if it shows up, gate behind a `last_seen_at < 1.minute.ago` check before the write.

Land as a single commit (or 2–3 grouped commits mirroring 3.16a/b/c), retag `phase-4` to the green tree.

---

## Phase 4.5 — Slip candidates (defer if scope balloons; exit criteria still hold without them)

If Phase 4 runs hot, slip these to a Phase 4.5 follow-up doc:

1. **MCP stdio bridge.** `Mcp::StdioBridge` + supervisor `mcp.spawn` / `mcp.invoke` / `mcp.shutdown` RPC handlers. Required for stdio-only MCP servers (e.g. the GitHub MCP server). HTTP MCP (context7) satisfies the workflows.md:3024 exit criterion without stdio.

2. **Monaco editor upgrade.** Memory + files editors move from `<textarea>` to Monaco via the `esm.sh` CDN. Monaco worker stub strategy per workflows.md § 13.1. Importmap pin + `monaco_controller.js`. Decision deferred to 4.5 because plain textarea is functional and not in any exit criterion.

3. **Action Cable cursor-replay-from-message.** Chat reconnects today rely on Solid Cable's `message_retention: 1.day` to deliver missed events; but a client that reconnects from a stale cursor doesn't tell the server where it was. Phase 4.5 adds `ChatChannel#replay(from_cursor:)` that loads `message.content_blocks` after the cursor and re-broadcasts. `TerminalChannel` already covers reattach scrollback via `tmux capture-pane` (Task 4.9).

4. **Linux namespaces for `run_shell`.** Today (Task 4.15): rlimits + uid drop (if supervisor root) + env scrub + pgroup. 4.5 adds `unshare(2)` (Linux-only) so `run_shell` runs in its own PID + network namespace. macOS dev never gets this; the gap is documented in Open items.

5. **MCP rich JSON-schema validation.** `Tool::Internal.validation_error` (Phase 3.16b) does minimal required-key + top-level-type checks. MCP tools may declare richer schemas; if a real MCP server's input schema breaks dispatch, swap to `json-schema` gem or `dry-schema`.

---

## Critical files map (Phase 4 additions)

```
config/routes.rb                                         # +terminals, +mcp_servers, +tests, +discoveries
config/puma.rb                                           # +on_worker_boot exporting PUMA_WORKER_INDEX
config/initializers/agents_supervisor_client.rb          # +boot-replay leader gate
config/initializers/workspace_bootstrap.rb               # +boot-replay leader gate (same helper)
config/initializers/content_security_policy.rb           # §15.7 activated
config/recurring.yml                                     # +sweep_expired_sessions, +sweep_terminals
config/importmap.rb                                      # +xterm + xterm addons

db/migrate/<ts>_add_expires_at_to_sessions.rb
db/migrate/<ts>_create_terminal_sessions.rb
db/migrate/<ts>_create_mcp_servers.rb
db/migrate/<ts>_create_mcp_tools.rb

app/models/session.rb                                    # +include Sweepable
app/models/session/sweepable.rb
app/models/terminal_session.rb
app/models/terminal_session/sweepable.rb
app/models/mcp_server.rb
app/models/mcp_server/enableable.rb
app/models/mcp_server/discoverable.rb
app/models/mcp_tool.rb
app/models/tool/mcp.rb
app/models/message/streamable.rb                         # restore :mcp arm in infer_source + available_tools
app/models/tool_call/executable.rb                       # replace :mcp placeholder
app/models/tool/internal/run_shell.rb                    # supervisor RPC dispatch
app/models/tool/internal/run_shell/in_process.rb         # fallback for tests

app/services/agents_supervisor/client.rb                 # +call() RPC method + SupervisorError
app/services/terminal/tmux_manager.rb
app/services/mcp/http_client.rb
app/services/mcp/outbound_guard.rb

app/jobs/session/sweep_job.rb
app/jobs/terminal/sweep_job.rb
app/jobs/mcp/discovery_job.rb

app/channels/terminal_channel.rb
app/controllers/application_controller.rb                # expiry check + touch_and_maybe_rotate!
app/controllers/terminals_controller.rb
app/controllers/mcp_servers_controller.rb
app/controllers/mcp_servers/tests_controller.rb
app/controllers/mcp_servers/discoveries_controller.rb

app/views/terminals/{index,show}.html.erb
app/views/mcp_servers/{index,show,new,edit,_form}.html.erb
app/views/mcp_servers/tests/create.turbo_stream.erb
app/views/mcp_servers/discoveries/create.turbo_stream.erb

app/javascript/controllers/terminal_controller.js
app/assets/stylesheets/components/terminal.css

bin/agents_supervisor                                    # v2 rewrite: pool, line cap, single-writer, tmux + mcp + shell handlers

test/fixtures/terminal_sessions.yml
test/fixtures/mcp_servers.yml
test/fixtures/mcp_tools.yml
test/models/session/sweepable_test.rb
test/models/terminal_session_test.rb
test/models/terminal_session/sweepable_test.rb
test/models/mcp_server_test.rb
test/models/mcp_server/discoverable_test.rb
test/models/mcp_tool_test.rb
test/models/tool/mcp_test.rb
test/services/terminal/tmux_manager_test.rb
test/services/mcp/http_client_test.rb
test/services/mcp/outbound_guard_test.rb
test/jobs/session/sweep_job_test.rb
test/jobs/terminal/sweep_job_test.rb
test/jobs/mcp/discovery_job_test.rb
test/channels/terminal_channel_test.rb
test/controllers/application_controller_test.rb
test/controllers/terminals_controller_test.rb
test/controllers/mcp_servers_controller_test.rb
test/controllers/mcp_servers/tests_controller_test.rb
test/integration/supervisor_v2_test.rb
test/integration/csp_test.rb
test/initializers/boot_replay_test.rb
test/system/terminal_test.rb
test/system/mcp_test.rb
```

---

## Open items (Phase 4 only — surface as you hit them, don't pre-decide)

- **`async` gem revisit.** Phase 4 sticks with plain threads + `IO.select` + `Concurrent::FixedThreadPool` per workflows.md:773 and § 19. Surface only if `IO.select` + the bounded pool show pump-latency issues under terminal load. The migration cost is significant (reactor ownership across pump threads); don't pay it without a concrete latency signal.

- **`bin/agents_supervisor` one process or two** (workflows.md § 19). The supervisor now owns the memory watcher + skills watcher + tmux + MCP + shell.run. If shutdown latency or restart blast radius becomes painful, split `bin/memory_watcher` (lightweight, watches files, emits notifications) from `bin/agents_supervisor` (heavyweight, owns child processes). Don't pre-decide.

- **Monaco CDN vs `monaco-editor-rails`** (workflows.md § 13.1). Default to CDN ESM via importmap when Monaco lands in 4.5. If cold-load time or worker-stub fragility bites, switch to the gem.

- **MCP stdio supervisor lifecycle on dev.** When 4.5 adds stdio bridge: cold-boot ordering matters — supervisor must finish spawning enabled MCP children before Puma sends an `mcp.invoke`. Today the supervisor client retries on `ENOENT`/`ECONNREFUSED`; extend to surface "supervisor not ready" 503s if MCP tools are invoked too early.

- **`mcp_server_disablements` child table vs status enum.** Phase 4 ships the **`status: :disabled` enum value** (one row mutation, no audit trail). If audit needs ("when was server X disabled and by whom") emerge in Phase 5, promote to a child table — schema-additive, not breaking.

- **`TerminalSession` TTL.** Default 1 hour via `MOP_TERMINAL_TTL_HOURS`. Single-user installs running overnight builds want longer; surface as an env knob, don't bake a longer default.

- **CSP `connect-src` allowlist for MCP SSE.** Server-side HTTP calls don't hit CSP. If an SSE-transport MCP server proxies to the browser, we'll need to allowlist its origin. Surface when the first SSE server lands.

- **`run_shell` uid drop without a privileged supervisor.** True uid drop needs the supervisor to start as root and `setuid()` for the child. Production deployments do that via a privileged unit; dev laptops don't. For Phase 4: rlimits + env scrub + audit log + admin-only gate stay the safety net. Don't pre-decide a deployment story — surface at Phase 5 (operations).

- **Worker-0 gate + Solid Queue concurrency overlap.** Task 4.4 keeps `Skill::ReloadJob`'s per-path `limits_concurrency` even though Worker-0 gating eliminates the boot-replay fan-out. Cost is negligible (one fast check per enqueue); benefit is defence-in-depth for non-boot enqueues (watcher, manifest reload via UI). Revisit if the concurrency-key infrastructure shows overhead.

- **Action Cable cursor replay on chat vs terminal.** They have different replay semantics: chat → `message.content_blocks` slice, terminal → `tmux capture-pane`. Don't unify the abstraction prematurely; ship two implementations in Phase 4 / 4.5 and refactor in Phase 5 if a pattern emerges across `SwarmChannel` (Phase 6) too.

- **`bin/agents_supervisor` reload during dev autoload.** When `bin/rails server` reloads Ruby classes, the long-running supervisor process does **not** reload. Phase 4 supervisor v2 has more Rails code (TmuxBridge, ShellBridge, MCP handlers run inside the supervisor); a class change requires a supervisor restart. Document in `docs/operations.md` and surface a friendly `bin/dev` warning if the supervisor is older than the Rails boot time.

- **`listen` polling vs FSEvents on macOS** (Phase 2 carry-over). No code change unless events go missing. Surface if reload jobs stop firing for an obvious disk write.

---

## Decisions logged during Phase 4 planning

These look like open questions but were closed during this plan — not deferred, decided.

- **Threading model: plain threads + `IO.select` + `Concurrent::FixedThreadPool(16)`.** Workflows.md:773 default. `async` migration deferred to Open items.

- **MCP server enable/disable: `status: :disabled` enum value, not a child table.** Workflows.md:156 left the choice to Phase 4; the enum value is already first-class and single-user installs don't benefit from non-repudiation.

- **`Tool::Internal` does NOT delegate to MCP.** Sibling `Tool::Mcp` registry. `Message::Streamable#infer_source` is the explicit dispatch table.

- **CDN ESM for Monaco when 4.5 lands** (not the `monaco-editor-rails` gem). Decision matches workflows.md § 13.1 default.

- **Phase 4 / 4.5 split is explicit, not hidden.** MCP stdio bridge, Monaco, Cable cursor-replay, and Linux namespaces for `run_shell` are 4.5 candidates — the executor decides during Phase 4 whether they fit. Exit criteria hold without them.

- **`Session::SweepJob` keeps `cookies.signed.permanent` (20-year cookie).** The DB row's `expires_at` is the real gate; aligning the cookie's `expires:` to the DB value is cosmetic and complicates rotation logic. Open item, low priority.

- **The boot-replay `limits_concurrency` stays** even after Worker-0 gating. Cost is negligible; benefit is defence-in-depth for non-boot enqueues.

---

## Self-review checklist (planning)

- [x] **Spec coverage** — every workflows.md § Phase 4 deliverable maps to a task above (or is explicitly marked Phase 4.5).
- [x] **Phase 3 carry-overs explicit** — Worker-0 gate (4.4), `McpTool` arm (4.12), `run_shell` rewrite (4.15) all named in Phase 3's open items.
- [x] **Concrete file paths** — every task names the file it touches.
- [x] **Failing test first** — each task starts from a red test, not from an implementation sketch.
- [x] **Verification commands present** — every task ends with a runnable assertion + expected output.
- [x] **Hardening gate predicted** — 12 items that mirror Phase 3's H1–H7.
- [x] **Open items separate from decisions** — workflows.md § 19 open items map cleanly into either "decided here" or "surface during execution".
- [x] **Scope budget realistic** — Phase 4 / 4.5 split documented; exit criteria hold without 4.5 work.
