# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

**Master of Puppets** is a Rails 8.1 application that hosts an LLM chat / agent platform:

- **Chat** — multi-turn LLM conversations with streaming, tool use (internal + MCP), and per-user skill packs.
- **Scheduled Jobs** — cron-scheduled prompts that run on the LLM and record `JobRun`s.
- **Swarm** — multi-agent "missions": a goal is decomposed into `SwarmAssignment`s, each dispatched to an `AgentProfile` backed by a tmux worker. Auto-mode and manual-mode supported.
- **Skills** — Markdown SKILL.md files on disk, indexed via FTS, installable + enableable per user.
- **Memory** — Markdown notes on disk under `${MOP_HOME}/memory`, indexed via FTS, hot-reloaded.
- **Terminals** — tmux-backed PTY sessions piped to ActionCable.
- **MCP servers** — outbound HTTP MCP tool calls per user.

The app is single-user-bootstrap by default (first user becomes admin via `User#promote_bootstrap_to_admin`).

## Common commands

```bash
# Setup (idempotent — installs gems, prepares DB)
bin/setup --skip-server
bin/setup --reset        # full DB reset

# Run dev (web + Solid Queue worker + agents supervisor via foreman)
bin/dev

# Tests — parallelized, multi-DB
bin/rails test
bin/rails test test/models/skill_test.rb
bin/rails test test/models/skill_test.rb:42        # by line
bin/rails test:system                              # Capybara/Selenium

# CI pipeline (rubocop + bundler-audit + importmap audit + brakeman + tests + seeds)
bin/ci

# Lint / security (run individually)
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit

# Background queue (only needed standalone; bin/dev runs it)
bin/rails solid_queue:start --recurring
```

`Procfile.dev` runs three processes: `web` (Puma), `worker` (Solid Queue with recurring jobs from `config/recurring.yml`), and `supervisor` (`bin/agents_supervisor`). All three are required for the full app to function locally.

## Architecture

### Multi-database SQLite

The app uses Rails 8's multi-DB SQLite setup (`config/database.yml`): `primary`, `content`, `cache`, `queue`, `cable`. `solid_cache` / `solid_queue` / `solid_cable` provide the cache / queue / pub-sub layers — no Redis. FTS lives in the `content` DB (`memory_file_fts`, `skill_fts`).

### The agents_supervisor sidecar (`bin/agents_supervisor`)

A separate Ruby process owning anything Rails can't safely do itself:

- **`tmux` bridges** — `terminal.*` and `swarm.*` JSON-RPC methods spawn `mop-term-<id>` and `mop-swarm-<id>` tmux sessions; output is piped to FIFOs under `tmp/sockets/`. The Rails web process tails the FIFOs and broadcasts via `TerminalChannel` / `SwarmChannel`.
- **`shell.run`** — runs commands for the `run_shell` internal tool with rlimits, env scrubbing, and process-group SIGTERM/SIGKILL on timeout.
- **Memory + Skills watchers** — `Listen` on `${MOP_HOME}/memory` and `${MOP_HOME}/skills` emit server-initiated `memory.changed` / `skills.changed` JSON-RPC notifications that Puma's `AgentsSupervisor::Client` consumes (one subscriber per worker; cold-start replay via `Memory::FullReindexJob` + `Skill::ReloadJob` gated to worker 0 by `BootReplayLeader`).

Talks to Rails over a UNIX socket (`MOP_SUPERVISOR_SOCKET`, default `tmp/sockets/agents_supervisor.sock`, mode 0600). Wire format is line-delimited JSON-RPC 2.0. Every per-connection write (responses + notifications) goes through a single `SizedQueue`-backed writer thread so frames never interleave. Session-id / assignment-id values from the wire are `Integer(value)`-coerced at the chokepoint before reaching any tmux argv or `pipe-pane` shell string — this is the only thing preventing shell-metachar injection there.

`shell.run` is admin-only and `MOP_ENABLE_RUN_SHELL` defaults to `false` in production.

### `${MOP_HOME}` workspace

`config.x.mop_home` (defaults to `storage/workspace/`) holds:

```
${MOP_HOME}/
├── memory/       # MEMORY.md + Markdown notes; FTS-indexed, watcher-broadcast
├── skills/       # SKILL.md files; FTS-indexed, watcher-broadcast
├── profiles/     # Agent-profile authored on disk
├── artifacts/    # Run outputs
└── logs/
```

`WorkspaceBootstrap.run` (in `config/initializers/workspace_bootstrap.rb`) creates the dirs and copies `db/seeds/skills/**/SKILL.md` into `${MOP_HOME}/skills/` on first boot. The on-disk file is the source of truth — seed copy never clobbers.

### LLM provider abstraction

`Llm::Client.for(provider:)` returns one of `Llm::Anthropic`, `Llm::OpenAi`, `Llm::Ollama`, each implementing `Llm::Adapter#stream(messages:, tools:, model:, system:)` which yields normalized events (`:message_start`, `:text_delta`, `:tool_use_start`, `:content_block_stop`, `:message_stop`, …) and returns a usage hash. **Tests stub at this boundary** via `LlmStubs` (`test/support/llm_stubs.rb`) — never against a live API, never via VCR cassettes (per `Gemfile` comment). `webmock` blocks net access in tests except for localhost (chromedriver).

### Message advance loop

`Message::Streamable#advance!` (in `app/models/message/streamable.rb`) is the heart of chat:

1. Flip to `:streaming`, call `llm_adapter.stream(...)`, broadcast each event.
2. If the model emitted tool calls, run them (`Tool::Internal.invoke` or `Tool::Mcp.invoke`), append tool result messages, **recurse with `iteration + 1`** up to `MAX_TOOL_ITERATIONS = 10`.
3. Otherwise finalize and record usage.
4. `Llm::RateLimited` → enqueue `Message::AdvanceJob` with `wait: retry_after`.

Available tools = `Tool::Internal.allowed_for(user)` (admin-only `run_shell`) + `Tool::Mcp.allowed_for(user)` + `enabled_skills.flat_map(&:tool_definitions)`. For swarm-worker chat sessions, `enabled_skills` is the intersection of the agent profile's declared skills with the owning user's enablements — never the user's full kit.

### Eventable + concern-driven models

Models compose behavior from concerns rather than inheritance:

- **Shared** (`app/models/concerns/`): `Eventable`, `Searchable` (FTS).
- **Model-specific** (`app/models/<model>/`): e.g. `ChatSession::Archivable`, `Message::Streamable`, `Message::Costable`, `SwarmMission::Decomposable`, `SwarmMission::Cancellable`, `Skill::Loadable`, `Skill::Installable`, etc.

`Eventable` adds `has_many :events, as: :eventable` and a `track_event(action, **particulars)` that records `Current.user`, `Current.ip_address`, `Current.user_agent`. The polymorphic `events` table is the audit log.

### Current attributes drive multi-tenancy

`Current.user` is set by `ApplicationController#set_current` from the signed `:session_id` cookie. Models lean on this via `belongs_to :user, default: -> { Current.user }` — **don't pass `user:` explicitly when creating user-owned records inside a controller**; let the default fire. Tests must set `Current.user` (or rely on the `test_helper.rb` setup that fixtures it from `sessions(:one)`).

### Background jobs: `_now` / `_later` pattern

Domain methods come in pairs: `decompose!` runs synchronously; `decompose_later` enqueues. Example: `SwarmMission#dispatch_later`, `Message#advance_later`. `ApplicationJob` `discard_on ActiveJob::DeserializationError` so best-effort `*_later` jobs drop cleanly when the record vanished between enqueue and perform.

Recurring jobs (`config/recurring.yml`): `scheduler_tick` (every minute, fires due `ScheduledJob`s), `swarm_orchestrator` (every 30s, advances active missions, concurrency-limited to 1), `sweep_terminals`, `sweep_expired_sessions`, `sweep_stale_job_runs`, `event_prune`.

### Routes — RESTful nesting, never custom actions

See `config/routes.rb`. Sub-resources live under `scope module: :parent_resource` (e.g. `chat_sessions/messages_controller.rb`, `swarm_missions/cancellations_controller.rb`). Pause/start/archive are modeled as singular sub-resources with `create`/`destroy` (`resource :pause, only: %i[create destroy]`) rather than custom actions.

### Frontend

- Hotwire (Turbo + Stimulus), importmap (no Node bundler).
- **Pure custom CSS** under `app/assets/stylesheets/` — no Tailwind, no Bootstrap. Uses CSS `@layer`, OKLCH colors, custom-property tokens, logical properties (see `docs/style-guide.md`). When editing styles, prefer the existing semantic vars (`--color-ink`, `--color-canvas`, etc.) over raw values. The repo-level `modern-css` skill encodes this.
- ActionCable channels: `ChatChannel`, `JobsChannel`, `SwarmChannel`, `TerminalChannel`, `DashboardChannel`.

### Tests

- Minitest, parallelized (`parallelize(workers: :number_of_processors)`).
- Fixtures under `test/fixtures/`. Note `set_fixture_class swarm_mission_cancellations: "SwarmMission::Cancellation"` in `test_helper.rb` — namespaced models need this mapping.
- `ControllerSignInHelpers#sign_in_as(user)` POSTs to `session_path` to get a real signed cookie (Rack::Test can't sign cookies directly).
- `LlmStubs.with_stubbed_llm(adapter) { ... }` / `with_decomposition(plan) { ... }` swap `Llm::Client.for`. **No live LLM calls, no VCR.**
- `WebMock.disable_net_connect!(allow_localhost: true, allow: %w[127.0.0.1 ::1])` — selenium/chromedriver loopback is whitelisted.

## Code conventions

The project follows the patterns documented in `docs/patterns-and-best-practices.md` (concern-driven models, intention-revealing APIs, scopes that tell stories, thin controllers, `_now`/`_later` jobs, multi-tenancy via `Current`) and `docs/style-guide.md` (custom-CSS design system). Two repo-level skills, **`rails-patterns`** and **`modern-css`**, encode these — invoke them before writing Ruby/Rails or CSS so output matches the team's idioms instead of generic Rails/CSS conventions.

Ruby style: `rubocop-rails-omakase`. Don't fight it.

## When changing the supervisor / shell / tmux paths

- Any value flowing from JSON-RPC params to a shell-evaluated tmux argument **must** pass through `Integer(value)` at the chokepoint (`coerce_session_id` / `coerce_assignment_id` in `bin/agents_supervisor`). Don't add a new method that bypasses it.
- `run_shell` env scrubbing list (`SCRUBBED` in `ShellBridge`) is the canonical list of "secrets the child must never see" — add to it if you introduce new env-borne secrets.
- The supervisor and Rails-side `AgentsSupervisor::Client` communicate over line-delimited JSON-RPC; any new method needs both a `case` arm in `handle_request` (in `bin/agents_supervisor`) and a caller path in Rails.
