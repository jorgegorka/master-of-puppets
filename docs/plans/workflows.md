# Master of Puppets — Rails 8.1 port of Hermes Workspace

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Phase 1 below uses checkbox (`- [ ]`) syntax for tracking; later phases give specs precise enough that a fresh "Phase N task list" can be written from them before that phase begins (see [§ Phase task-list discipline](#phase-task-list-discipline)).

**Goal:** Recreate the Hermes Workspace AI agent workspace (~85 HTTP endpoints, ~13 feature areas) as a standalone Ruby on Rails 8.1 application with full feature parity, no FastAPI gateway dependency.

**Architecture:** Rails owns UI + agent backend. Direct calls to Anthropic / OpenAI-compatible providers via Ruby SDKs. SQLite (multi-DB) + ActiveRecord for everything persistent; markdown/skill files on disk are source of truth, AR rows are the index. Long-running concerns (MCP stdio, tmux, file watcher) live in a single supervisor process out-of-band from Puma.

**Tech stack:** Rails 8.1.3, Ruby 3.4.8, SQLite ≥ 2.1, Hotwire (Turbo + Stimulus), Solid Queue / Cache / Cable, Propshaft, Importmap. Adds in Phase 1: `anthropic ~> 1.41` (official Anthropic Ruby SDK), `faraday`, `fugit` (cron parsing), `bcrypt`, `listen`. CSS is pure custom (no Tailwind, no Bootstrap, no utility framework) built on `@layer`, OKLCH color, semantic custom properties, and logical properties — served via Propshaft. See `docs/style-guide.md`. Phase-4 adds: `xterm` + addons via importmap, `monaco-editor` via importmap (lazy-loaded with worker workaround).

---

## 1. Context

We are recreating https://github.com/outsourc-e/hermes-workspace (Node/React, ~85 HTTP endpoints, ~40 data shapes, ~13 feature areas) as a standalone Rails 8.1 application in this repo (`/Users/jorge/Sites/rails/master-of-puppets`).

Three framing decisions:

1. **Full feature parity** — no scope cut. Chat, Memory, Files, Terminal, Skills, MCP, Jobs, Settings, Dashboard, Swarm, Conductor, Agent Profiles, Themes. Phased rollout only.
2. **Standalone**: Rails owns both UI and the agent backend. We talk directly to Anthropic and OpenAI-compatible providers via Ruby SDKs and re-implement memory, skills, and MCP tool-calling in Ruby. No FastAPI gateway.
3. **SQLite + ActiveRecord for everything** persistent. Memory markdown files and skill directories remain on disk as source of truth; AR rows are an index/cache.

The current Rails 8.1 scaffold is a clean slate (no commits yet). Hotwire (Turbo + Stimulus), Solid Queue / Cache / Cable, SQLite multi-DB (production only — Phase 1 extends this), Propshaft, Importmap, Kamal, and Active Storage are wired but `app/` is empty besides the application skeleton.

### 1.1 Explicit non-goals (for v1)

These are Hermes features we deliberately defer; capturing them keeps scope honest:

- **"Modes" presets** (named model/setting bundles in Zustand). Out of scope for v1.
- **Sound notifications** (Web Audio API chimes). Out of scope.
- **Workspace Checkpoints / code-review approval system** (different from `SwarmCheckpoint`). Out of scope.
- **Native desktop / Electron build.** Web only.
- **Voice input.** Out of scope.
- **Multi-region / multi-tenant SaaS.** Single-instance, single-or-few-user.
- **Provider expansion beyond Anthropic, OpenAI-compatible, Ollama.** Google, OpenRouter, Nous Portal device-code, MiniMax, Z.AI/GLM, Kimi are deferrable; the `ProviderConfig` schema supports them, but adapters are not built until requested.

## 2. Codebase patterns

This plan follows the Talento HQ Rails idioms documented in `docs/patterns-and-best-practices.md`. The concrete adaptations for this app:

- **Concern-driven models**: every behavioral capability (`Streamable`, `Forkable`, `Eventable`, `Searchable`, `Installable`, `Enableable`, `Pausable`, `Cancellable`…) lives in `app/models/concerns/` (shared) or `app/models/<model>/` (model-specific). Models are thin shells composing many concerns.
- **Intention-revealing APIs**: domain verbs (`fork`, `pause`, `resume`, `cancel`, `install`, `enable`), never generic names. Boolean methods come in pairs (`streaming?`/`done?`).
- **Smart association defaults via `Current`**: `belongs_to :user, default: -> { Current.user }`; children derive ancestors. Callers never pass `user:` explicitly.
- **State changes are child records, not enum flips.** `ScheduledJob` pause status = `has_one :pause`; `SwarmMission` cancellation = `has_one :cancellation`; `Skill` install/enable = `has_many :installations` / `has_one :enablement`.
- **Business-language scopes**: `ChatSession.active`, `Message.streaming`, `Skill.enabled`. `case`-based `indexed_by(param)`/`sorted_by(param)` to keep controllers thin.
- **Sparing callbacks**: derived fields, cache touches, `_commit`-suffixed `_later` enqueues only. Business logic in explicit methods.
- **Thin controllers**: load → call **one** model method → respond. 3–5 lines each.
- **RESTful resource nesting**: every state change is a nested `resource :…`, never a custom action route.
- **`_now`/`_later` pattern**: every async op has a sync method (`message.advance!`) and an async wrapper (`message.advance_later`) that enqueues a 3-line job.
- **Automatic multi-tenancy in jobs**: `ActiveJob` extension in `config/initializers/active_job.rb` captures `Current.user` at enqueue and restores it via `Current.set(user:) { … }` at perform.
- **`Eventable` is the audit trail.** Every state-changing method calls `track_event :action_name, particulars: { … }` inside its transaction. `Event` is the single polymorphic table.
- **External adapters live in `app/services/`; domain logic lives on models.** `Llm::Anthropic`, `Mcp::HttpClient`, `Terminal::TmuxManager` are services. `MemoryFile#reindex!`, `Skill#install_for(user)`, `ToolCall#execute`, `SwarmMission#decompose!` are model methods.
- **Style:** expanded conditionals over guard clauses; `private` not surrounded by blank line, body indented 2 spaces under it; bang only on methods that have a non-bang counterpart; class methods at top, public next, private last; private methods sorted vertically by invocation order.

### 2.1 Adaptation: `Current` and `Eventable`

The patterns doc is from a multi-tenant app keyed on `Current.account`/`Current.session`/`board`. This app is keyed on **`Current.user`** with no `board`. Adaptations applied throughout:

- `Current` (`app/models/current.rb`) exposes `attribute :user` and `attribute :session`. `ApplicationController#set_current` before-action populates them from `cookies.signed[:session_id]`.
- `Eventable` writes events with `eventable:` polymorphic (no `board`). Signature: `track_event(action, creator: Current.user, **particulars)`. See § 6 for the full concern.
- Test setup uses `Current.session = sessions(:one)` (see § 11 for fixture sketch).

### 2.2 Primary keys

Use **integer primary keys** (Rails 8 default). The patterns doc uses UUIDs because Postgres supports them natively; SQLite UUID-as-text would buy us nothing here and adds complexity. Public-facing IDs that need to be unguessable (`ChatSession#share_token`, `ApiToken#prefix`) get their own random columns.

## 3. High-level architecture

```
┌────────────── Browser (Hotwire + xterm.js + Monaco) ──────────────┐
│   Turbo Frames/Streams over Action Cable (Solid Cable / SQLite)   │
└──────────────────────────────┬────────────────────────────────────┘
                               │ HTTP + WebSocket
┌──────────────────────────────▼────────────────────────────────────┐
│   Puma (Rails 8.1)                                                │
│   ├── Controllers (RESTful + Turbo)                               │
│   ├── Channels (Chat, Terminal, Swarm, Dashboard, Jobs)           │
│   └── Services (Llm, Mcp, Skills, Memory, Files, Conductor, …)    │
└──────┬──────────────────────────────────┬─────────────────────────┘
       │ Solid Queue (background)         │ UNIX socket / JSON-RPC
       ▼                                  ▼
┌─────────────────┐               ┌─────────────────────────────────┐
│ Solid Queue     │               │ bin/agents_supervisor           │
│ workers         │               │   - tmux sessions (terminal +   │
│ - ChatStreamJob │               │     swarm workers)              │
│ - SchedulerTick │               │   - MCP stdio child processes   │
│ - Orchestrator  │               │   - file watcher for memory     │
└─────────────────┘               └─────────────────────────────────┘
       │                                  │
       ▼                                  ▼
┌────────────────── SQLite (multi-DB) ──────────────────────────────┐
│ primary.sqlite3 (domain), content.sqlite3 (FTS5),                 │
│ cache.sqlite3, queue.sqlite3, cable.sqlite3                       │
└───────────────────────────────────────────────────────────────────┘
       │
       ▼
┌────────────────── Filesystem at MOP_HOME ─────────────────────────┐
│ memory/MEMORY.md + memory/*.md, skills/<cat>/<slug>/SKILL.md,     │
│ profiles/<slug>/{config.yml,runtime.json}, artifacts/             │
└───────────────────────────────────────────────────────────────────┘
```

**Critical architectural choice:** the three long-running concerns (MCP stdio servers, terminal/swarm tmux sessions, memory file watcher) all violate Puma's request lifecycle. They share one dedicated supervisor process (`bin/agents_supervisor`), not three separate decisions. See § 8 for the supervisor protocol.

## 4. Domain model (ActiveRecord)

All persisted in SQLite. Models in `app/models/`. Internal canonical message shape mirrors Anthropic (content blocks, `tool_use` / `tool_result` blocks) — Anthropic is richer than OpenAI and down-converting is lossless; the inverse isn't.

**Conventions every model applies** (per `patterns-and-best-practices.md`):

- `belongs_to :user, default: -> { Current.user }` wherever a user is the implicit owner. Children derive ancestors via lambda defaults.
- **State-change child records, not enum flips** (table § 4.1).
- **Concerns compose behavior** — a `Message` is `Streamable, Costable, Searchable, Forkable, Eventable`; a `Skill` is `Loadable, SecurityAnalyzable, Installable, Enableable, Searchable, Eventable`.
- **Boolean methods in pairs** (`streaming?` / `done?`), **action methods use verbs** (`stream`, `fork`, `pause`, `resume`).
- JSON columns: SQLite has no `jsonb`. Use `t.json :name` (Rails 8 maps it to `text` with `JSON` serializer).

### 4.1 Top-level entities

| Model | Key fields | Notes |
|---|---|---|
| `User` | `email:string`, `password_digest:string`, `role:integer` (enum `member`/`admin`), `single_user_bootstrap:boolean` | `has_secure_password`. Single-user mode auto-signs-in if `User.count == 1` and `SINGLE_USER_PASSWORD` matches (§ 10.1). |
| `Session` | `user:references`, `user_agent:string`, `ip_address:string`, `last_seen_at:datetime` | Web-session record (similar to Rails 8 generator). Cookie carries `session.id` signed. |
| `ApiToken` | `user:references`, `name:string`, `scopes:json` (array), `prefix:string` (8 chars, indexed), `token_digest:string`, `last_used_at:datetime` | Bearer auth for `/v1/responses`. Full token displayed once at creation. Lookup: by `prefix`, verify with `bcrypt`-style digest. |
| `ChatSession` | `user:references`, `title:string`, `model:string`, `provider:string`, `forked_from_id:integer` (self-ref nullable), `pinned:boolean`, `archived_at:datetime`, `share_token:string` (16 hex chars, unique, nullable), `last_active_at:datetime` | |
| `Message` | `chat_session:references`, `role:integer` (enum `system`/`user`/`assistant`/`tool`), `content_blocks:json`, `stream_cursor:json`, `status:integer` (enum `pending`/`streaming`/`completed`/`failed`/`rate_limited`/`cancelled`), `prompt_tokens:integer`, `completion_tokens:integer`, `cache_read_tokens:integer`, `cache_creation_tokens:integer`, `cost_usd:decimal(12,6)`, `model:string`, `provider:string`, `created_at`, `updated_at` | `content_blocks` is an array of Anthropic-shaped blocks: `{type: "text", text: "…"}`, `{type: "thinking", thinking: "…"}`, `{type: "tool_use", id: "toolu_…", name, input, tool_call_id}`, `{type: "tool_result", tool_use_id, content, is_error}`. `stream_cursor` schema in § 7.2. |
| `ToolCall` | `message:references`, `provider_tool_id:string` (the LLM's `toolu_…` id), `name:string`, `source:integer` (enum `internal`/`mcp`/`skill`), `input:json`, `output:json`, `status:integer` (enum `pending`/`running`/`succeeded`/`failed`/`cancelled`), `error_message:text`, `started_at:datetime`, `finished_at:datetime` | Source of record for tool calls. Active Storage `has_many_attached :artifacts` for file outputs. `provider_tool_id` is what the LLM round-trips. |
| `MemoryFile` | `path:string` (unique), `title:string`, `tags:json` (array), `content_digest:string` (sha256), `byte_size:integer`, `disk_mtime:datetime`, `created_at`, `updated_at` | Lives on `primary` DB. Body lives on disk at `${MOP_HOME}/memory/<path>`. `memory_files_fts` (FTS5 virtual table) lives in **`content` DB** holding searchable body text — see § 4.3. |
| `Skill` | `slug:string` (unique), `name:string`, `category:string`, `description:text`, `manifest:json` (parsed frontmatter), `source_path:string`, `origin:integer` (enum `builtin`/`agent_created`/`marketplace`), `security_level:integer` (enum `safe`/`low`/`medium`/`high`), `body_digest:string`, `discovered_at:datetime` | Disk source of truth. SKILL.md frontmatter format in § 4.5. Per-user installation/enablement live in child tables below. |
| `SkillInstallation` | `skill:references`, `user:references`, `accepted_security_level:integer`, `accepted_at:datetime` | One row per (skill, user). Non-repudiation. |
| `SkillEnablement` | `skill:references`, `user:references`, `enabled_at:datetime` | One row per (skill, user). Presence = enabled. |
| `McpServer` | `user:references`, `name:string`, `transport_type:integer` (enum `http`/`sse`/`stdio`), `url:string`, `command:string`, `args:json` (array), `env_payload:text` (Rails 8 `encrypts :env_payload`; JSON serialized hash of name→value), `auth_type:integer` (enum `none`/`bearer`/`basic`), `auth_payload:text` (encrypted), `tool_mode:integer` (enum `all`/`include_list`/`exclude_list`), `include_tools:json`, `exclude_tools:json`, `status:integer` (enum `unknown`/`reachable`/`error`/`disabled`), `last_tested_at:datetime`, `last_error:text`, `socket_path:string` (set by supervisor for stdio) | One row per server. `env_payload` holds the entire `{ENV_VAR: value}` map encrypted (simpler than the original "env_keys array + encrypted column" sketch). |
| `McpTool` | `mcp_server:references`, `name:string`, `description:text`, `input_schema:json`, `discovered_at:datetime` | Cached. Replaced wholesale on `discover_tools!`. |
| `TerminalSession` | `user:references`, `tmux_session_name:string` (unique, e.g. `mop-term-42`), `cols:integer`, `rows:integer`, `cwd:string`, `status:integer` (enum `starting`/`live`/`detached`/`terminated`), `last_activity_at:datetime` | TTL sweep in `Terminal::SweepJob`. |
| `ScheduledJob` | `user:references`, `name:string`, `cron:string`, `prompt:text`, `model:string`, `skill_slugs:json` (array), `next_run_at:datetime`, `last_run_at:datetime` | Pause is a `has_one :pause` (child record below). |
| `JobRun` | `scheduled_job:references`, `started_at:datetime`, `finished_at:datetime`, `status:integer` (enum `running`/`succeeded`/`failed`/`cancelled`), `output:text`, `exit_code:integer`, `prompt_tokens:integer`, `completion_tokens:integer`, `cost_usd:decimal(12,6)` | One per execution. |
| `SwarmMission` | `user:references`, `title:string`, `goal:text`, `state:integer` (enum `planning`/`dispatching`/`executing`/`reviewing`/`blocked`/`complete`/`cancelled`), `created_by_id:integer` (User) | State machine § 4.4. |
| `SwarmAssignment` | `swarm_mission:references`, `agent_profile:references`, `task:text`, `rationale:text`, `depends_on:json` (array of assignment ids), `state:integer` (enum `pending`/`dispatched`/`running`/`blocked`/`completed`/`failed`/`cancelled`), `review_required:boolean` | |
| `SwarmCheckpoint` | `swarm_assignment:references`, `state_label:string`, `runtime_state:json`, `files_changed:json`, `commands_run:json`, `result:text`, `blocker:text`, `next_action:text`, `raw:text` | Human-visible milestones parsed from worker output. |
| `SwarmEvent` | `swarm_mission:references`, `swarm_assignment_id:integer` (nullable), `kind:string`, `message:text`, `data:json`, `occurred_at:datetime` | Append-only machine log driving replay. (Note: this is distinct from `Event` — `SwarmEvent` is high-frequency worker telemetry, `Event` is the audit trail.) |
| `AgentProfile` | `slug:string` (unique), `display_name:string`, `role:string`, `model:string`, `provider:string`, `specialties:json` (array), `avoid_tasks:json` (array), `cwd:string`, `status:integer` (enum `online`/`away`/`offline`), `enabled:boolean` | Per swarm worker. Seeded from `db/seeds/agent_profiles.yml`. |
| `AgentProfileSkill` | `agent_profile:references`, `skill:references` | Join. |
| `ProviderConfig` | `provider:string` (unique, e.g. `anthropic`, `openai`, `ollama`), `base_url:string`, `api_key:text` (encrypted), `default_model:string`, `enabled:boolean` | `encrypts :api_key`. |
| `UserSetting` | `user:references`, `theme:string`, `accent:string`, `editor_font_size:integer`, `sidebar_collapsed:boolean`, `notifications_enabled:boolean`, `usage_threshold:integer` | One per user. |
| `Event` | `creator_id:integer` (User, nullable for system events), `action:string` (e.g. `"chat_session_forked"`, `"skill_installed"`, `"tool_call_invoked"`), `eventable_type:string`, `eventable_id:integer`, `particulars:json`, `ip:string`, `user_agent:string`, `occurred_at:datetime` | Single polymorphic audit table. Drives audit log, webhooks, activity timeline. **Not `AuditEvent`** — single source of truth named `Event`. |

### 4.2 State-change child tables (per § 2 pattern)

Migration list — each is a small table with `parent_id`, `user:references` (default `Current.user`), and `created_at`. Concerns are listed in parens.

| Table | Concern on parent | Routes (singular `resource :…`) |
|---|---|---|
| `chat_session_archives` | `ChatSession::Archivable` → `archived?`, `archive`, `unarchive` | `resource :archive` |
| `chat_session_pins` | `ChatSession::Pinnable` | `resource :pin` |
| `scheduled_job_pauses` | `ScheduledJob::Pausable` → `paused?`, `pause`, `resume` | `resource :pause` |
| `swarm_mission_cancellations` | `SwarmMission::Cancellable` → `cancelled?`, `cancel` | `resource :cancellation` |
| `mcp_server_disablements` | `McpServer::Enableable` → mirror enable as child for parity | (or use bool flag — pick at Phase 4) |

`SkillInstallation` and `SkillEnablement` already listed in § 4.1 follow the same pattern but live on the join model side.

### 4.3 Multi-DB layout

Extend `config/database.yml` so **every environment** (not just production) has both `primary` and `content`. Plus the existing `cache`, `queue`, `cable` in production. Phase-1 migration adds the `content` DB; Phase 2 fills it with `MemoryFile` FTS.

```yaml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  primary:
    <<: *default
    database: storage/development.sqlite3
  content:
    <<: *default
    database: storage/development_content.sqlite3
    migrations_paths: db/content_migrate

test:
  primary:
    <<: *default
    database: storage/test.sqlite3
  content:
    <<: *default
    database: storage/test_content.sqlite3
    migrations_paths: db/content_migrate

production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  content:
    <<: *default
    database: storage/production_content.sqlite3
    migrations_paths: db/content_migrate
  cache:
    <<: *default
    database: storage/production_cache.sqlite3
    migrations_paths: db/cache_migrate
  queue:
    <<: *default
    database: storage/production_queue.sqlite3
    migrations_paths: db/queue_migrate
  cable:
    <<: *default
    database: storage/production_cable.sqlite3
    migrations_paths: db/cable_migrate
```

**Models that live on `content`** use `connects_to`:

```ruby
class ContentRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :content, reading: :content }
end

class MessageFts < ContentRecord
  self.table_name = "messages_fts"
  # virtual FTS5 model — created with raw SQL in migration
end
```

**`Searchable` concern** (`app/models/concerns/searchable.rb`) is what owns FTS bridging — it sets up triggers (or writes to the shadow table from `_commit` callbacks) so `Message`/`MemoryFile`/`Skill` rows on `primary` keep `*_fts` on `content` in sync. Tokenizer: `porter`. Ranking: `bm25()`.

### 4.4 State machines

```
SwarmMission.state:
  planning → dispatching → executing ⇄ reviewing
                                     ↘ blocked → executing | cancelled
                                     → complete
  any → cancelled (via SwarmMission::Cancellable#cancel)

SwarmAssignment.state:
  pending → dispatched → running → completed | failed | blocked | cancelled
  blocked → running (when user resolves)

Message.status:
  pending → streaming → completed
                     ↘ failed
                     ↘ rate_limited (retryable)
                     ↘ cancelled

ToolCall.status:
  pending → running → succeeded | failed | cancelled

TerminalSession.status:
  starting → live ⇄ detached → terminated (via SweepJob TTL or explicit close)
```

Transitions are model methods that run inside a transaction with `track_event` calls. No `aasm` / `state_machines` gem — explicit `def transition_to(*)` methods.

### 4.5 SKILL.md format

Skills on disk follow Hermes / Claude skill conventions:

```
${MOP_HOME}/skills/<category>/<slug>/SKILL.md
${MOP_HOME}/skills/<category>/<slug>/<asset files>
```

`SKILL.md` body:

```markdown
---
name: deep-research
description: Multi-step research with citations
category: search-research
triggers:
  - "research X"
  - "investigate Y"
security_level: medium
allowed_tools:
  - web_search
  - read_file
---

# Body content (system prompt / instructions)
```

`Skill::Loadable#load_from_path!` parses YAML frontmatter into `manifest` and writes a `body_digest` of the body. `Skill::SecurityAnalyzable` derives `security_level` from frontmatter, then upgrades on heuristics (shell-command mention bumps to `medium`, network calls bump to `high`, etc. — see Phase 3).

## 5. Service layer

`app/services/` is reserved for **adapters to external systems**. Domain logic lives on models. Callbacks are used sparingly — derived fields, cache touches, and `_commit`-suffixed async enqueues. The `Eventable` concern + `track_event` is the cross-cutting hook for audit/webhooks/notifications; `ActiveSupport::Notifications` is reserved for non-audit instrumentation.

```
app/services/
├── llm/
│   ├── client.rb              # Provider-agnostic façade (§ 7.1)
│   ├── anthropic.rb           # Wraps official `anthropic` gem
│   ├── open_ai.rb             # Faraday adapter (chat + tools + streaming SSE)
│   ├── ollama.rb              # Faraday adapter
│   ├── message_normalizer.rb  # OpenAI shape ↔ Anthropic content_blocks
│   └── retry_wrapper.rb       # Jitter + retry-after; surfaces 429/529 as Message.status="rate_limited"
├── mcp/
│   ├── http_client.rb         # HTTP/SSE transport (in-request)
│   ├── stdio_bridge.rb        # UNIX-socket client to bin/agents_supervisor (stdio MCP)
│   └── responses_translator.rb # JSON-RPC framing
├── terminal/
│   ├── tmux_manager.rb        # new-session / send-keys / capture-pane / kill-session
│   └── stream_pump.rb         # Bridges tmux pipe-pane FIFO → Action Cable
├── conductor/
│   └── prompts.rb             # Renders decomposition / review prompt templates from disk
└── llm_responses_adapter.rb   # OpenAI /v1/responses ↔ internal shape (inbound API translation)
```

**Everything else folds into models** (per § 4 concerns). Reference table — services we considered, where the logic actually lives:

| Original service idea | Becomes |
|---|---|
| `Skills::Loader` | `Skill.reload_from_disk` (class) + `Skill#load_from_path!` |
| `Skills::SecurityAnalyzer` | `Skill::SecurityAnalysis` PORO under `app/models/skill/` |
| `Skills::Installer` | `skill.install_for(user)` |
| `Memory::Indexer` | `MemoryFile.reindex_all` + `MemoryFile#reindex!` |
| `Memory::Writer` | `MemoryFile#write(content, user:)` |
| `Memory::Search` | `MemoryFile.matching(query)` scope |
| `Memory::WikilinkGraph` | `MemoryFile#backlinks` / `MemoryFile.wikilink_graph` |
| `Files::Sandbox` | `WorkspacePath` value object (`app/models/workspace_path.rb`) |
| `Files::TreeLoader` | `WorkspaceFile.tree(root:)` |
| `Tools::Executor` | `tool_call.execute` (via `ToolCall::Executable` concern) |
| `Tools::InternalRegistry` | class-method registry on `Tool::Internal` (single-table inheritance not needed — registry of plain Ruby classes keyed by name) |
| `Swarm::Dispatcher` | `SwarmAssignment.dispatch_ready` class method |
| `Swarm::OrchestratorLoop` | `SwarmMission.advance_all_active` class method |
| `Swarm::CheckpointParser` | `SwarmCheckpoint.parse(raw)` |
| `Swarm::WorkerBridge` | `AgentProfile#send_keys(input)` (delegates to `Terminal::TmuxManager`) |
| `Conductor::Decomposer` | `swarm_mission.decompose!` |
| `Mcp::Registry` | `McpServer.tools_for(name)` + scopes |
| `Mcp::ToolInvoker` | `mcp_tool.invoke(input)` |
| `Mcp::Discovery` | `mcp_server.discover_tools!` sync + `discover_tools_later` |

### 5.1 LLM gem choices

- **Anthropic:** official `anthropic ~> 1.41` (https://github.com/anthropics/anthropic-sdk-ruby). Requires Ruby 3.2+ (we're on 3.4.8). Typed streaming events, tool use, thinking blocks, files, batches, prompt caching.
- **OpenAI-compatible:** thin Faraday adapter. `ruby-openai` lags on `/v1/responses` and is harder to keep aligned with both our outbound (Phase 1) and inbound `/v1/responses` (Phase 7) responsibilities. We own this adapter.
- **Ollama:** Faraday adapter, same shape as OpenAI-compatible with different base URL.

## 6. The `Eventable` concern (adapted)

Patterns doc Eventable writes `board.events.create!`. Our adaptation:

```ruby
# app/models/concerns/eventable.rb
module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  def track_event(action, creator: Current.user, **particulars)
    if should_track_event?
      events.create!(
        action: "#{eventable_prefix}_#{action}",
        creator: creator,
        particulars: particulars,
        ip: Current.ip_address,
        user_agent: Current.user_agent,
        occurred_at: Time.current
      )
    end
  end

  def event_was_created(event)
    # Override hook
  end

  private
    def should_track_event?
      true
    end

    def eventable_prefix
      self.class.name.demodulize.underscore
    end
end
```

`Event` has an `after_create_commit :notify_eventable` that calls `eventable&.event_was_created(self)` — the model-specific override hook for broadcasting Turbo Streams / firing webhooks.

## 7. Streaming: Action Cable + Solid Queue (not `ActionController::Live`)

`ActionController::Live` pins a Puma thread for the whole completion (minutes), starves the pool, and offers no clean resume after tool calls. Instead, the `_now`/`_later` pattern:

### 7.1 `Llm::Client` interface

```ruby
# app/services/llm/client.rb
module Llm
  module Client
    extend self

    # @return [Llm::Adapter] one of Anthropic / OpenAi / Ollama
    def for(provider:)
      case provider
      when "anthropic" then Anthropic.new(ProviderConfig.find_by!(provider: provider))
      when "openai"    then OpenAi.new(ProviderConfig.find_by!(provider: provider))
      when "ollama"    then Ollama.new(ProviderConfig.find_by!(provider: provider))
      end
    end
  end
end

# app/services/llm/adapter.rb — every adapter implements this contract
module Llm
  module Adapter
    # Yields events as plain Ruby hashes. The contract is the union below.
    #
    # @param messages [Array<Hash>] Anthropic-shaped messages (role + content_blocks)
    # @param tools    [Array<Hash>] tool definitions (name, description, input_schema)
    # @param model    [String]
    # @yieldparam event [Hash]
    # @return [Hash] usage summary { prompt_tokens:, completion_tokens:, cache_read_tokens:, cache_creation_tokens:, finish_reason: }
    def stream(messages:, tools:, model:, &block)
      raise NotImplementedError
    end
  end
end
```

**Event union** (every adapter normalizes to these, including OpenAI-compat which gets translated by `MessageNormalizer`):

```ruby
{ type: :message_start, message_id: "msg_…", model: "…" }
{ type: :content_block_start, index: 0, block: { type: "text", text: "" } }
{ type: :content_block_start, index: 1, block: { type: "thinking", thinking: "" } }
{ type: :content_block_start, index: 2, block: { type: "tool_use", id: "toolu_…", name: "read_file", input: {} } }
{ type: :text_delta, index: 0, text: "Hello" }
{ type: :thinking_delta, index: 1, thinking: "Let me…" }
{ type: :tool_use_input_delta, index: 2, partial_json: "{\"path\":\"R" }
{ type: :content_block_stop, index: 0 }
{ type: :message_stop, finish_reason: "tool_use" }
{ type: :error, error_class: "RateLimited", retry_after: 12, message: "…" }
```

### 7.2 `Message#advance!` — the streaming engine

`stream_cursor` is a JSON value with shape `{ "block_index" => Integer, "byte_offset" => Integer, "last_event_at" => ISO8601 }`. It's persisted after every successful event so a worker crash mid-stream can resume.

Pseudocode (full implementation is a Phase 1 task):

```ruby
# app/models/concerns/message/streamable.rb
module Message::Streamable
  extend ActiveSupport::Concern

  def advance!
    transaction do
      update!(status: :streaming) unless streaming?
    end

    adapter = Llm::Client.for(provider: provider)
    usage = adapter.stream(messages: prompt_messages, tools: available_tools, model: model) do |event|
      apply_stream_event!(event)            # mutates content_blocks + stream_cursor
      broadcast_event(event)                # ChatChannel.broadcast_to(chat_session, event)
    end

    if needs_tool_loop?
      run_tool_calls!                       # synchronously executes each tool_use block
      advance!                              # recurse — next LLM turn after tool_results
    else
      finalize!(usage)
    end
  rescue Llm::RateLimited => e
    update!(status: :rate_limited, error_message: e.message)
    Message::AdvanceJob.set(wait: e.retry_after).perform_later(self)
  rescue => e
    update!(status: :failed, error_message: e.message)
    track_event :failed, error: e.class.name
    raise
  end
end
```

**Tool-call loop stays inside `advance!`.** When the LLM emits `tool_use`, the model synchronously calls `tool_call.execute` (which records start/finish, writes `track_event :invoked` inside its transaction), persists the `tool_result` block, and recurses. One user-visible turn = one outer call to `advance!`, regardless of N tool calls.

**`ChatStreamJob`** (renamed `Message::AdvanceJob` for clarity — see § 8) is a 3-line wrapper: `def perform(message) = message.advance!`.

### 7.3 Turbo Stream contract

```ruby
# Browser subscribes via ChatChannel.stream_for(chat_session)
# Each event is broadcast as a Turbo Stream payload:
turbo_stream.append("chat-session-#{chat_session.id}-messages",
  partial: "messages/stream_event", locals: { message:, event: })
# stream_event partial dispatches on event[:type] and renders the corresponding morph
```

For initial render: `MessagesController#create` returns `turbo_stream.append("…")` with a `<turbo-cable-stream-source>` subscribing to `chat_session:#{id}`.

### 7.4 Free wins from this design

- Conversation export (markdown + JSON) reads `content_blocks` directly.
- Session forking (`message.fork!` via `Forkable` concern) creates a child `ChatSession`, writes `track_event :forked`.
- Resume after crash: replay events from `stream_cursor` (cheap because we persisted everything).
- Full audit trail via `Eventable`.

## 8. Real-time channels

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    def connect
      self.current_user = find_verified_user
      logger.add_tags("ActionCable", "User #{current_user.id}")
    end
    private
      def find_verified_user
        session_id = cookies.signed[:session_id]
        Session.find_by(id: session_id)&.user or reject_unauthorized_connection
      end
  end
end

# app/channels/
ChatChannel       → stream_for chat_session       # chat deltas, tool calls, thinking
TerminalChannel   → stream_for terminal_session   # stdout, exit, resize
SwarmChannel      → stream_for swarm_mission      # state changes, checkpoints, kanban
DashboardChannel  → stream "dashboard"            # metrics, incidents
JobsChannel       → stream_for scheduled_job      # run status
```

Use Turbo Streams over Action Cable for non-token UI updates (kanban card moves, settings changes) — keeps the JS layer thin.

## 9. Routes (corrected)

Per `patterns-and-best-practices.md §4.2`, every state-changing action is a nested `resource :…`, never a custom `post :action`. Pause/resume become POST/DELETE on a single resource.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "dashboard#show"

  resource :session, only: %i[new create destroy]  # web sign-in

  namespace :api do
    namespace :v1 do
      resources :sessions
      resources :messages
      resources :responses, only: %i[create]   # OpenAI /v1/responses compatibility
      resources :chat_completions, only: %i[create]  # /v1/chat/completions legacy
    end
  end

  resources :chat_sessions, path: "chat" do
    scope module: :chat_sessions do
      resources :messages, only: %i[create]
      resources :forks,    only: %i[create]    # POST /chat/:id/forks
      resource  :archive,  only: %i[create destroy]
      resource  :pin,      only: %i[create destroy]
    end
  end

  resource :memory, controller: "memory", only: [:show] do
    scope module: :memory do
      # `id` matches any path because memory files use slashed paths
      resources :files,    only: %i[show update create destroy],
                constraints: { id: %r{[^?]+} }, defaults: { format: :html }
      resources :searches, only: %i[create]
    end
  end

  resource :files, controller: "files", only: [:show] do
    scope module: :files do
      resources :nodes, only: %i[index show create update destroy]  # tree=index, read=show, write=update
    end
  end

  resources :skills, only: %i[index show update destroy] do
    scope module: :skills do
      resources :installations, only: %i[create destroy]
      resource  :enablement,    only: %i[create destroy]
    end
  end
  resources :skill_marketplace_entries, only: [:index], path: "skills/marketplace"

  resources :mcp_servers, path: "mcp" do
    scope module: :mcp_servers do
      resource :test, only: %i[create]  # POST /mcp/:id/test → McpServers::TestsController
    end
  end

  resources :terminal_sessions, path: "terminal", only: %i[index show create destroy] do
    scope module: :terminal_sessions do
      resource :size, only: %i[update]
    end
  end

  resources :scheduled_jobs, path: "jobs" do
    scope module: :scheduled_jobs do
      resource  :pause, only: %i[create destroy]
      resources :runs,  only: %i[index show create]
    end
  end

  resources :swarm_missions, path: "swarm/missions" do
    scope module: :swarm_missions do
      resources :assignments,  only: %i[create update]
      resource  :cancellation, only: %i[create]
    end
  end
  get "/swarm/kanban", to: "swarm_kanbans#show"
  resources :agent_profiles, path: "swarm/agents"

  resource :dashboard, only: [:show]
  resource :settings, only: %i[show update] do
    scope module: :settings do
      resources :providers, only: %i[index show update] do
        scope module: :providers do
          resource :test, only: %i[create]
        end
      end
      resources :api_tokens, only: %i[index create destroy]
      resource  :oauth_device_code, only: %i[create]
    end
  end
end
```

Every controller follows the `Cards::ClosuresController` shape: include a scope concern (`ChatSessionScoped`, `SwarmMissionScoped`, `ScheduledJobScoped`, …) for resource loading, then `create`/`update`/`destroy` are 3–5 lines calling one model method.

## 10. Background jobs (Solid Queue)

```
app/jobs/
├── message/
│   └── advance_job.rb               # 3-line: message.advance!
├── scheduler_tick_job.rb            # Recurring (every 1 min); enqueues due ScheduledJobs
├── scheduled_job/
│   └── runner_job.rb                # Executes one ScheduledJob → JobRun
├── swarm/
│   └── orchestrator_loop_job.rb     # Recurring; advances missions
├── mcp/
│   └── discovery_job.rb             # Discovers tools for an McpServer
├── memory/
│   └── indexer_job.rb               # Recomputes FTS5 for a memory path
└── terminal/
    └── sweep_job.rb                 # Recurring; kills sessions past detach TTL
```

`config/recurring.yml` (overwrites scaffold default):

```yaml
production: &recurring
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: "every hour at minute 12"
  scheduler_tick:
    class: SchedulerTickJob
    schedule: "every 1 minute"
  swarm_orchestrator:
    class: Swarm::OrchestratorLoopJob
    schedule: "every 30 seconds"
  terminal_sweep:
    class: Terminal::SweepJob
    schedule: "every 5 minutes"

development:
  <<: *recurring
```

(Solid Queue picks up recurring entries when started with `--recurring` — `Procfile.dev` includes that flag.)

Use the `fugit` gem (MIT) inside `SchedulerTickJob` to parse `ScheduledJob#cron` and compute `next_run_at`. **Do not use `rufus-scheduler`** — in-process, doesn't survive Puma restarts cleanly.

**All jobs are 3-line wrappers** (per `patterns-and-best-practices.md §4.4`):

```ruby
class Message::AdvanceJob < ApplicationJob
  def perform(message) = message.advance!
end

class SchedulerTickJob < ApplicationJob
  def perform = ScheduledJob.run_all_due
end

class ScheduledJob::RunnerJob < ApplicationJob
  def perform(scheduled_job) = scheduled_job.run!
end

class Swarm::OrchestratorLoopJob < ApplicationJob
  def perform = SwarmMission.advance_all_active
end

class Memory::IndexerJob < ApplicationJob
  def perform(path) = MemoryFile.reindex(path)
end

class Terminal::SweepJob < ApplicationJob
  def perform = TerminalSession.sweep_idle
end

class Mcp::DiscoveryJob < ApplicationJob
  def perform(mcp_server) = mcp_server.discover_tools!
end
```

Each sync method has a paired `_later` enqueuing wrapper on the model (`message.advance_later`, `mcp_server.discover_tools_later`). The `ActiveJob` extension at `config/initializers/active_job.rb` captures `Current.user` at enqueue and restores via `Current.set(user:) { … }` at perform — never pass `user:` to `.perform_later`.

### 10.1 `Current` and ActiveJob extension

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :session, :ip_address, :user_agent
  # Use Current.set(user: x) { … } directly for scoped overrides — that's the
  # CurrentAttributes built-in. No need for a custom Current.with wrapper.
end

# config/initializers/active_job.rb
module CurrentUserActiveJobExtensions
  extend ActiveSupport::Concern

  prepended do
    attr_reader :captured_user
    self.enqueue_after_transaction_commit = true
  end

  def initialize(...)
    super
    @captured_user = Current.user
  end

  def serialize
    super.merge("captured_user" => @captured_user&.to_global_id&.to_s)
  end

  def deserialize(job_data)
    super
    if gid = job_data["captured_user"]
      @captured_user = GlobalID::Locator.locate(gid)
    end
  end

  def perform_now
    if @captured_user
      Current.set(user: @captured_user) { super }
    else
      super
    end
  end
end

ActiveSupport.on_load(:active_job) do
  ActiveJob::Base.prepend CurrentUserActiveJobExtensions
end
```

## 11. Long-running supervisor (`bin/agents_supervisor`)

A dedicated Ruby process that owns:

- **Tmux sessions** for terminals (`mop-term-<id>`) and swarm workers (`mop-swarm-<slug>`).
- **MCP stdio child processes** (one per enabled `McpServer` with `transport_type=stdio`).
- **Memory file watcher** (`listen` gem) — enqueues `Memory::IndexerJob` on changes.
- Exposes a **UNIX-domain-socket JSON-RPC bridge** at `tmp/sockets/agents_supervisor.sock`. Puma + Solid Queue connect to send keystrokes, invoke MCP tools, query supervisor state.

Lifecycle: Procfile.dev for local; Kamal accessory for production. Restarts independently of Puma.

**Why one supervisor, not three:** PTY/tmux FDs die with the owning process and can't be reattached across Puma deploys. MCP stdio servers can't multiplex across forked Puma workers. File watcher must survive class-reload. All three want the same lifecycle.

### 11.1 Process model

- Main thread: `EventMachine`-free; uses `Async` (`async`/`async-io` gems, added in Phase 4) or plain `Thread.new` + `IO.select`. Phase 4 task decides; default is **plain threads + `IO.select`** to avoid an extra gem.
- One thread per: socket-accept loop, listen-watcher, tmux output pumps (per session), MCP child stdin/stdout pump.
- Graceful shutdown: `TRAP("TERM")` → kill all tmux/MCP children → flush pending IPC → exit.

### 11.2 JSON-RPC protocol

Newline-delimited JSON over UNIX socket (`tmp/sockets/agents_supervisor.sock`).

```jsonc
// Request
{"jsonrpc":"2.0","id":7,"method":"terminal.create","params":{"session_id":42,"cols":120,"rows":40,"cwd":"/Users/jorge"}}
// Response
{"jsonrpc":"2.0","id":7,"result":{"tmux_session_name":"mop-term-42"}}
// Notification (server-initiated, no id)
{"jsonrpc":"2.0","method":"terminal.output","params":{"session_id":42,"chunk":"$ ls\n"}}
```

Methods (will grow per phase):
- `terminal.create`, `terminal.input`, `terminal.resize`, `terminal.close`
- `mcp.spawn`, `mcp.invoke`, `mcp.shutdown`
- `swarm.spawn_worker`, `swarm.send_keys`, `swarm.close_worker`
- `memory.changed` (notification, server → client; client = `Memory::IndexerJob` enqueuer)
- `health.ping`

`app/services/agents_supervisor/client.rb` wraps this for Puma/Solid Queue callers.

### 11.3 Startup ordering

`Procfile.dev`:
```
web:        bin/rails server -p 3000
worker:     bin/rails solid_queue:start --recurring
supervisor: bin/agents_supervisor
```

Supervisor must be running before any terminal/MCP/swarm operation; Puma queues operations and returns 503 with a friendly message if the socket is absent. Phase 4+ feature.

## 12. Filesystem layout (`MOP_HOME`, defaults to `Rails.root.join("storage/workspace")`)

Configurable via `MOP_HOME` env var. Layout:

```
$MOP_HOME/
├── memory/
│   ├── MEMORY.md
│   └── <topic>/<slug>.md          # arbitrary user/agent tree
├── skills/
│   └── <category>/<slug>/
│       ├── SKILL.md                # YAML frontmatter + body
│       └── <files>
├── profiles/
│   └── <slug>/
│       ├── config.yml              # mirror of AgentProfile for tool friendliness
│       └── runtime.json            # mirror of live state
├── artifacts/                      # tool output files (also tracked by Active Storage)
└── logs/
```

`app/models/workspace_path.rb` is the value object that guards path traversal. Every disk read/write goes through `WorkspacePath.resolve(root: MOP_HOME, raw: …)` which raises `WorkspacePath::EscapeAttempt` if the resolved real path is not under `MOP_HOME`.

## 13. Frontend stack

- **Pure custom CSS** — no Tailwind, no Bootstrap, no utility framework. Built on `@layer` (reset / base / components / modules / utilities / native / platform), OKLCH color for perceptual consistency across light/dark, semantic custom properties (`--color-ink`, `--color-canvas`, `--inline-space`, `--block-space`, …), and logical properties for RTL. Components configure via `--<name>-*` custom properties; variants override those rather than duplicating selectors. Served via Propshaft from `app/assets/stylesheets/` (`_global.css`, `base.css`, `utilities.css`, `buttons.css`, `inputs.css`, `cards.css`, `layout.css`, …). Canonical reference: `docs/style-guide.md`. 8 themes (Claude Official + Light, Claude Classic + Light, Slate + Light, Mono + Light) implemented as OKLCH custom-property sets keyed on `data-theme` attribute on `<html>`. Theme + accent selection persisted on `UserSetting` and applied through a Stimulus controller.
- **Stimulus controllers** per interactive component:
  - `chat_controller.js` — subscribes to `ChatChannel`, renders content blocks, tool-call pills, thinking accordion.
  - `terminal_controller.js` — wraps xterm.js, bridges to `TerminalChannel`.
  - `monaco_controller.js` — lazy-loads Monaco (see § 13.1) for `Files` and `Memory` editing.
  - `kanban_controller.js` — drag/drop for `SwarmKanbansController#show`.
  - `command_palette_controller.js` — `cmdk`-style global palette.
  - `voice_input_controller.js` — Web Speech API.
  - `theme_controller.js` — applies `data-theme` + `data-accent` to `<html>`.
- **Importmap pins** (added per phase):
  - Phase 1: nothing extra.
  - Phase 4 (Terminal): `xterm`, `@xterm/addon-fit`, `@xterm/addon-search`, `@xterm/addon-web-links`.
  - Phase 4 (Monaco): `monaco-editor` via CDN ESM (https://esm.sh) — workers loaded with `MonacoEnvironment.getWorkerUrl` returning data-URI worker stubs (lazy stub strategy; full quality in Phase 7 if needed).
  - Phase 7: `cmdk` for command palette, `chart.js` for dashboard.
- **Turbo Frames** for in-place section updates (settings panel, mission details). **Turbo Streams** for broadcast (kanban moves, new messages, job status).
- **PWA**: existing scaffold has `app/views/pwa/{manifest.json.erb,service-worker.js}` and commented routes. Uncomment in Phase 1.

### 13.1 Monaco-via-importmap caveat

Monaco assumes a bundler. With importmap, we use the CDN ESM build and supply worker stubs:

```js
// app/javascript/monaco_setup.js (loaded lazily)
self.MonacoEnvironment = { getWorker(_, label) { return new Worker(URL.createObjectURL(new Blob(["self.MonacoEnvironment={};importScripts('https://esm.sh/monaco-editor@0.52/min/vs/base/worker/workerMain.js')"],{type:"application/javascript"}))); } };
```

This is functional but slower than bundled workers. If quality bites in Phase 4, fall back to `monaco-editor-rails` gem (which serves Monaco assets from a Rails asset path). Decision deferred to Phase 4.

## 14. OpenAI compatibility surface (`/v1/responses`)

Hermes Workspace exposes an OpenAI-compatible inbound API so external clients (Cursor, Cline, etc.) can target it. Mirror this in Phase 7:

- `Api::V1::BaseController` — disables CSRF, requires `ApiToken` bearer auth (`Authorization: Bearer <prefix>.<secret>`), scopes everything to the token's user.
- `Api::V1::ResponsesController#create` — accepts OpenAI Responses shape, calls `LlmResponsesAdapter.to_internal(params)` to mint a `ChatSession`/`Message`, enqueues `Message::AdvanceJob`, streams SSE back in OpenAI's event format (translated from Anthropic content blocks by `LlmResponsesAdapter.to_openai(...)`).
- `Api::V1::ChatCompletionsController#create` — same for legacy `/v1/chat/completions`.

## 15. Security model

### 15.1 Auth modes

- **Single-user (default):** bootstrap a `User` from `SINGLE_USER_PASSWORD` env on first boot. `Current.user` middleware auto-signs-in when `User.count == 1` AND the session cookie matches AND the env var matches. Sessions stored via Rails 8 session store (`Session` model, httpOnly, SameSite=Strict, Secure in production).
- **Multi-user:** standard `has_secure_password` sign-in. Set `MOP_MULTI_USER=1` to disable single-user auto-sign-in even when `User.count == 1`.

### 15.2 API auth

Bearer `ApiToken` on `/v1/*` routes. Token format: `<8-char-prefix>.<32-char-secret>`. Lookup by prefix, verify secret with `BCrypt::Password`. Rate limit per `Rack::Attack`-style throttle in `config/initializers/rack_attack.rb` (Phase 7).

### 15.3 Network exemptions

Local-network exemption (parity with Hermes): 127.0.0.1, ::1, Tailscale 100.64.0.0/10, LAN ranges (10/8, 172.16/12, 192.168/16) exempt from password — **opt-in** via `MOP_LOCAL_EXEMPT=1`. Default off.

### 15.4 Fail-closed remote bind

If `HOST` is non-loopback AND no password configured, fail to boot unless `MOP_ALLOW_INSECURE_REMOTE=1`. Check is in `config/initializers/security_boot_check.rb`.

### 15.5 Path traversal

`WorkspacePath` value object and `MemoryFile#write` reject any path that escapes `MOP_HOME` after `File.realpath`. `WorkspaceFile.tree(root:)` applies the same guard. Tested with traversal probes (§ 17).

### 15.6 Encryption

`encrypts :api_key` on `ProviderConfig`, `encrypts :env_payload`, `encrypts :auth_payload` on `McpServer`. Rails 8 native encryption keys in `config/credentials.yml.enc`.

### 15.7 CSP

`config/initializers/content_security_policy.rb`:

```ruby
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.style_src   :self, :unsafe_inline  # xterm.js + monaco inline styles
  policy.script_src  :self, "https://esm.sh"  # Monaco CDN
  policy.worker_src  :self, :blob             # Monaco workers (blob URL stubs)
  policy.connect_src :self, "wss:", "ws:"
  policy.img_src     :self, :data, :blob
  policy.media_src   :self, :data
  policy.font_src    :self, :data
end
```

### 15.8 Audit (via `Eventable`)

Every state-changing model method calls `track_event :action, particulars: { … }` inside its transaction. `Event` is the polymorphic table. Examples:
- `Skill::Installable#install_for(user)` → `:installed`
- `McpServer` create → `:created` (explicit in factory method, not callback)
- `ToolCall::Executable#execute` → `:invoked` then `:succeeded`/`:failed`
- `Session` create → `:signed_in`

`event_was_created(event)` hook fires Turbo Stream + webhook side effects. `ActiveSupport::Notifications` is reserved for non-audit perf metrics.

## 16. Phased implementation roadmap

Each phase ships an end-to-end usable slice. No phase blocks on a later one.

### Phase task-list discipline

Phase 1 below is fully decomposed into bite-sized tasks. **Before starting Phases 2–7**, write a per-phase task list at `docs/plans/<phase-N>-<slug>.md` using `superpowers:writing-plans` (this brief gives you every interface, schema, and contract — the task list is then a mechanical translation). Each task: file paths, failing test, minimal impl, run command, expected output, commit.

---

### Phase 1 — Foundation + Chat MVP (~2-3 weeks)

**Goal:** A working chat UI with streaming completions and a sign-in flow.

**Files map (for orientation; each task creates a subset):**

```
Gemfile                                            # add anthropic, faraday, fugit, bcrypt, listen
config/database.yml                                # multi-DB in dev/test
config/cable.yml                                   # solid_cable in dev too (optional)
config/recurring.yml                               # see § 10
config/routes.rb                                   # § 9
config/application.rb                              # autoload lib/, MOP_HOME default
config/initializers/active_job.rb                  # § 10.1
config/initializers/content_security_policy.rb    # § 15.7
config/initializers/security_boot_check.rb        # § 15.4
config/credentials.yml.enc                         # generated; encrypts: api_key salt

db/migrate/<ts>_create_users.rb
db/migrate/<ts>_create_sessions.rb
db/migrate/<ts>_create_api_tokens.rb
db/migrate/<ts>_create_chat_sessions.rb
db/migrate/<ts>_create_messages.rb
db/migrate/<ts>_create_tool_calls.rb
db/migrate/<ts>_create_provider_configs.rb
db/migrate/<ts>_create_user_settings.rb
db/migrate/<ts>_create_events.rb
db/migrate/<ts>_create_chat_session_archives.rb
db/migrate/<ts>_create_chat_session_pins.rb
db/content_migrate/<ts>_create_messages_fts.rb

app/models/application_record.rb                  # add ContentRecord too
app/models/content_record.rb
app/models/current.rb                              # § 10.1
app/models/user.rb
app/models/session.rb
app/models/api_token.rb
app/models/chat_session.rb
app/models/chat_session/archive.rb
app/models/chat_session/pin.rb
app/models/chat_session/forkable.rb
app/models/chat_session/archivable.rb
app/models/chat_session/pinnable.rb
app/models/message.rb
app/models/message/streamable.rb                   # § 7.2
app/models/message/costable.rb
app/models/message/forkable.rb
app/models/concerns/eventable.rb                   # § 6
app/models/concerns/searchable.rb                  # see § 4.3
app/models/tool_call.rb
app/models/tool_call/executable.rb                 # registry stub (real tools Phase 3)
app/models/provider_config.rb
app/models/user_setting.rb
app/models/event.rb

app/services/llm/client.rb                         # § 7.1
app/services/llm/adapter.rb                        # abstract module
app/services/llm/anthropic.rb
app/services/llm/open_ai.rb
app/services/llm/ollama.rb
app/services/llm/message_normalizer.rb
app/services/llm/retry_wrapper.rb

app/channels/application_cable/connection.rb
app/channels/application_cable/channel.rb
app/channels/chat_channel.rb

app/controllers/application_controller.rb         # set_current, require_sign_in
app/controllers/sessions_controller.rb
app/controllers/dashboard_controller.rb           # stub home page
app/controllers/chat_sessions_controller.rb
app/controllers/chat_sessions/messages_controller.rb
app/controllers/chat_sessions/forks_controller.rb
app/controllers/chat_sessions/archives_controller.rb
app/controllers/chat_sessions/pins_controller.rb
app/controllers/settings_controller.rb
app/controllers/settings/providers_controller.rb
app/controllers/concerns/chat_session_scoped.rb

app/jobs/application_job.rb                        # leave default
app/jobs/message/advance_job.rb                    # 3-liner

app/views/sessions/new.html.erb
app/views/dashboard/show.html.erb
app/views/chat_sessions/index.html.erb
app/views/chat_sessions/show.html.erb
app/views/chat_sessions/new.html.erb
app/views/chat_sessions/messages/_message.html.erb
app/views/chat_sessions/messages/_stream_event.turbo_stream.erb
app/views/layouts/application.html.erb            # data-theme, Turbo, nav
app/views/settings/show.html.erb
app/views/settings/providers/index.html.erb
app/views/settings/providers/show.html.erb

app/javascript/controllers/chat_controller.js
app/javascript/controllers/theme_controller.js

Procfile.dev
bin/dev
bin/agents_supervisor                              # Phase 1 stub: listen on socket, no real ops

test/fixtures/users.yml
test/fixtures/sessions.yml
test/fixtures/chat_sessions.yml
test/fixtures/messages.yml
test/fixtures/provider_configs.yml
test/test_helper.rb                                # Current.session = sessions(:one) helper

test/models/...                                    # one test file per model + concern
test/controllers/...
test/channels/chat_channel_test.rb
test/system/sign_in_test.rb
test/system/streaming_chat_test.rb
```

#### Task 1.1: Gemfile + bundle

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems to Gemfile**

Insert after the existing `gem "image_processing"` line:

```ruby
# AI provider SDKs
gem "anthropic", "~> 1.41"
gem "faraday", "~> 2.10"

# Cron parsing for ScheduledJob
gem "fugit", "~> 1.11"

# Password hashing
gem "bcrypt", "~> 3.1.7"

# Memory dir watcher (used by bin/agents_supervisor)
gem "listen", "~> 3.9"
```

- [ ] **Step 2: Bundle install**

Run: `bundle install`
Expected: `Bundle complete!` with no resolver errors. `Gemfile.lock` updates.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Phase 1: add gems for anthropic, cron, bcrypt, listen"
```

#### Task 1.2: Multi-DB development/test configuration

**Files:**
- Modify: `config/database.yml`
- Create: `db/content_migrate/.keep`

- [ ] **Step 1: Replace `config/database.yml` with the layout from § 4.3**

(Use the full block in § 4.3 of this plan.)

- [ ] **Step 2: Create the empty migration dir**

```bash
mkdir -p db/content_migrate && touch db/content_migrate/.keep
```

- [ ] **Step 3: Run setup**

Run: `bin/rails db:setup`
Expected: development + test DBs created for both `primary` and `content`. No errors.

- [ ] **Step 4: Commit**

```bash
git add config/database.yml db/content_migrate
git commit -m "Phase 1: extend multi-DB layout to dev/test (adds content DB)"
```

#### Task 1.3: `Current` + `Eventable` + base CSS scaffold

**Files:**
- Create: `app/models/current.rb`
- Create: `app/models/concerns/eventable.rb`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Write failing test for Current**

`test/models/current_test.rb`:
```ruby
require "test_helper"
class CurrentTest < ActiveSupport::TestCase
  test "stores user and session attributes" do
    Current.user = User.new(email: "a@b.com")
    assert_equal "a@b.com", Current.user.email
  end
end
```

- [ ] **Step 2: Run, expect FAIL (`uninitialized constant Current`)**

Run: `bin/rails test test/models/current_test.rb`
Expected: `NameError: uninitialized constant Current`.

- [ ] **Step 3: Implement `Current`**

`app/models/current.rb`:
```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :session, :ip_address, :user_agent

  def with(user: nil, **other, &block)
    set_args = { user: user || self.user }.merge(other.transform_values { _1 || nil })
    self.class.set(**set_args.compact, &block)
  end
end
```

- [ ] **Step 4: Pass test, commit**

Run: `bin/rails test test/models/current_test.rb`
Expected: 1 run, 0 failures.

```bash
git add app/models/current.rb test/models/current_test.rb
git commit -m "Phase 1: add Current attributes"
```

- [ ] **Step 5: Write failing test for Eventable**

`test/models/eventable_test.rb`:
```ruby
require "test_helper"

class EventableTest < ActiveSupport::TestCase
  class Thing < ApplicationRecord
    self.table_name = "events"  # piggyback an existing table for the dummy class
    include Eventable
  end

  test "track_event writes an Event row" do
    skip "wait for Event model"
  end
end
```

(We'll un-skip after Event migration in Task 1.5.)

- [ ] **Step 6: Implement Eventable** (file per § 6)

- [ ] **Step 7: Commit**

```bash
git add app/models/concerns/eventable.rb test/models/eventable_test.rb
git commit -m "Phase 1: add Eventable concern (Event model lands in Task 1.5)"
```

- [ ] **Step 8: Set up base CSS scaffold**

The app uses pure custom CSS served via Propshaft — no framework, no build step. Create the layer scaffold under `app/assets/stylesheets/` (canonical reference: `docs/style-guide.md`):

- `_global.css` — root design tokens (OKLCH raw palette + semantic aliases for color, the `--inline-space`/`--block-space` rhythm, `--text-*` type scale, `--z-*` scale, named easings, focus-ring vars) **and** the layer declaration:
  ```css
  @layer reset, base, components, modules, utilities, native, platform;
  ```
- `base.css` — element styles (html, body, headings, links) in `@layer base`.
- `utilities.css` — `.flex`, `.gap`, `.pad`, `.margin`, `.txt-*`, `.center`, `.full-width`, etc., in `@layer utilities`.
- `application.css` — top-level entry that pulls the above in via `@import` (Propshaft) in layer order.

Component files (`buttons.css`, `inputs.css`, `cards.css`, `dialog.css`, `layout.css`, `header.css`, `animation.css`, feature-specific files) land as features ship; Phase 1 only needs `_global.css` + `base.css` + `utilities.css` + `application.css` to bootstrap.

Verify the layout already references `stylesheet_link_tag "application"` (scaffolded with Propshaft). No `bin/dev`-style watcher is needed — Propshaft serves the files directly.

Expected: stylesheets present, page renders with base typography, no console errors loading `/assets/application.css`.

- [ ] **Step 9: Add theme attribute to layout**

In `app/views/layouts/application.html.erb`, change `<html>` to:
```erb
<html lang="en" data-theme="<%= Current.user&.user_setting&.theme || "claude-official" %>" data-accent="<%= Current.user&.user_setting&.accent || "indigo" %>">
```

The 8 themes (Claude Official + Light, Claude Classic + Light, Slate + Light, Mono + Light) are OKLCH custom-property sets keyed on `[data-theme="…"]` selectors inside `_global.css`; switching the attribute swaps the palette without re-rendering.

- [ ] **Step 10: Commit**

```bash
git add app/assets/stylesheets app/views/layouts/application.html.erb
git commit -m "Phase 1: bootstrap CSS layer scaffold + wire data-theme on <html>"
```

#### Task 1.4: User + Session + sign-in flow

**Files:**
- Create: `db/migrate/<ts>_create_users.rb`, `db/migrate/<ts>_create_sessions.rb`
- Create: `app/models/user.rb`, `app/models/session.rb`
- Create: `app/controllers/application_controller.rb` (rewrite), `app/controllers/sessions_controller.rb`
- Create: `app/views/sessions/new.html.erb`
- Modify: `config/routes.rb`
- Create: `test/fixtures/users.yml`, `test/fixtures/sessions.yml`, `test/system/sign_in_test.rb`

- [ ] **Step 1: Generate migrations**

```bash
bin/rails generate migration CreateUsers email:string:uniq password_digest:string role:integer single_user_bootstrap:boolean
bin/rails generate migration CreateSessions user:references user_agent:string ip_address:string last_seen_at:datetime
```

- [ ] **Step 2: Run migrations**

Run: `bin/rails db:migrate`
Expected: both tables created on `primary`.

- [ ] **Step 3: Write failing model + system tests**

`test/models/user_test.rb`:
```ruby
require "test_helper"
class UserTest < ActiveSupport::TestCase
  test "has_secure_password sets digest" do
    u = User.create!(email: "a@b.com", password: "supersecret123")
    assert u.authenticate("supersecret123")
  end
end
```

`test/system/sign_in_test.rb` (uses Capybara):
```ruby
require "application_system_test_case"
class SignInTest < ApplicationSystemTestCase
  test "user signs in" do
    User.create!(email: "a@b.com", password: "supersecret123")
    visit new_session_path
    fill_in "Email", with: "a@b.com"
    fill_in "Password", with: "supersecret123"
    click_button "Sign in"
    assert_text "Dashboard"
  end
end
```

- [ ] **Step 4: Run, expect FAIL**

`bin/rails test test/models/user_test.rb` → FAIL (no `User` class).

- [ ] **Step 5: Implement User**

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include Eventable
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one  :user_setting, dependent: :destroy
  has_many :chat_sessions, dependent: :destroy

  enum :role, member: 0, admin: 1
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  after_create :create_default_settings
  private
    def create_default_settings
      create_user_setting!(theme: "claude-official", accent: "indigo")
    end
end
```

```ruby
# app/models/session.rb
class Session < ApplicationRecord
  belongs_to :user
  before_create { self.last_seen_at ||= Time.current }
end
```

- [ ] **Step 6: Add routes**

Replace `config/routes.rb` with the full block in § 9 (or, for this task, the subset for `:session` + `root "dashboard#show"`).

- [ ] **Step 7: Implement `SessionsController` + view**

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  skip_before_action :require_sign_in, only: %i[new create]

  def new; end

  def create
    user = User.find_by(email: params[:email]&.downcase)
    if user&.authenticate(params[:password])
      session = user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
      cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :strict, secure: Rails.env.production? }
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    Current.session&.destroy
    cookies.delete(:session_id)
    redirect_to new_session_path
  end
end
```

`app/views/sessions/new.html.erb`:
```erb
<%= form_with url: session_path, local: true, class: "auth-form" do |f| %>
  <h1>Sign in</h1>
  <% if flash[:alert] %><p class="alert"><%= flash[:alert] %></p><% end %>
  <label>Email <%= f.email_field :email, required: true %></label>
  <label>Password <%= f.password_field :password, required: true %></label>
  <%= f.submit "Sign in" %>
<% end %>
```

- [ ] **Step 8: Implement `ApplicationController#set_current`**

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :set_current
  before_action :require_sign_in

  private
    def set_current
      Current.session    = Session.find_by(id: cookies.signed[:session_id])
      Current.user       = Current.session&.user
      Current.ip_address = request.remote_ip
      Current.user_agent = request.user_agent
    end

    def require_sign_in
      redirect_to new_session_path unless Current.user
    end
end
```

- [ ] **Step 9: Add fixtures + helper**

`test/fixtures/users.yml`:
```yaml
one:
  email: jorge@example.test
  password_digest: <%= BCrypt::Password.create("supersecret123") %>
  role: 0
```

`test/fixtures/sessions.yml`:
```yaml
one:
  user: one
  user_agent: "Capybara/test"
  ip_address: "127.0.0.1"
  last_seen_at: <%= Time.current.iso8601 %>
```

`test/test_helper.rb` (append):
```ruby
class ActiveSupport::TestCase
  fixtures :all
  setup { Current.session = sessions(:one) if defined?(sessions) }
end
```

- [ ] **Step 10: Stub Dashboard**

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def show; end
end
```
`app/views/dashboard/show.html.erb`: `<h1>Dashboard</h1>`

- [ ] **Step 11: Run all tests**

Run: `bin/rails test`
Expected: `7 runs, 0 failures, 0 errors` (or similar — the count grows with each task).

Run: `bin/rails test:system`
Expected: `1 run, 0 failures, 0 errors` (sign-in flow passes).

- [ ] **Step 12: Commit**

```bash
git add db config app test
git commit -m "Phase 1: User + Session + sign-in flow with Current attributes"
```

#### Task 1.5: Event + Eventable wiring

**Files:**
- Create: `db/migrate/<ts>_create_events.rb`
- Create: `app/models/event.rb`
- Modify: `app/models/concerns/eventable.rb` (already created in 1.3)
- Modify: `test/models/eventable_test.rb`

- [ ] **Step 1: Migration**

```bash
bin/rails generate migration CreateEvents creator:references{null} action:string eventable_type:string eventable_id:integer particulars:json ip:string user_agent:string occurred_at:datetime
```

Edit the migration to add `t.index [:eventable_type, :eventable_id]` and `t.index :action`.

Run: `bin/rails db:migrate`
Expected: events table created.

- [ ] **Step 2: Implement Event model**

```ruby
# app/models/event.rb
class Event < ApplicationRecord
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :eventable, polymorphic: true
  after_create_commit :notify_eventable

  private
    def notify_eventable
      eventable.try(:event_was_created, self)
    end
end
```

- [ ] **Step 3: Un-skip and pass Eventable test**

`test/models/eventable_test.rb`:
```ruby
require "test_helper"
class EventableTest < ActiveSupport::TestCase
  test "track_event writes an Event row with prefixed action" do
    user = users(:one)
    Current.user = user
    assert_difference -> { Event.count }, +1 do
      user.track_event :signed_in, particulars: { ip: "127.0.0.1" }
    end
    assert_equal "user_signed_in", Event.last.action
  end
end
```

Make `User` `include Eventable` (already added in 1.4 — verify).

- [ ] **Step 4: Run, commit**

Run: `bin/rails test test/models/eventable_test.rb`
Expected: 1 run, 0 failures.

```bash
git add db app test
git commit -m "Phase 1: Event polymorphic table + Eventable wiring"
```

#### Task 1.6: ProviderConfig + UserSetting + ApiToken

**Files:**
- Create: 3 migrations, 3 models, 3 fixtures, 3 tests
- Modify: `config/credentials.yml.enc` (already exists; add active_record_encryption keys)

- [ ] **Step 1: Generate Rails-8 encryption keys**

Run: `bin/rails db:encryption:init`
Expected: outputs YAML you paste under `active_record_encryption:` in `config/credentials.yml.enc`.

```bash
bin/rails credentials:edit
# add the three keys printed by db:encryption:init
```

- [ ] **Step 2: Generate migrations**

```bash
bin/rails generate migration CreateProviderConfigs provider:string:uniq base_url:string api_key:text default_model:string enabled:boolean
bin/rails generate migration CreateUserSettings user:references theme:string accent:string editor_font_size:integer sidebar_collapsed:boolean notifications_enabled:boolean usage_threshold:integer
bin/rails generate migration CreateApiTokens user:references name:string scopes:json prefix:string:uniq token_digest:string last_used_at:datetime
```

Edit each migration to add `t.timestamps` (the generator includes it) and check `null: false` on key columns.

Run: `bin/rails db:migrate`
Expected: 3 tables created.

- [ ] **Step 3: Implement ProviderConfig**

```ruby
# app/models/provider_config.rb
class ProviderConfig < ApplicationRecord
  include Eventable
  encrypts :api_key
  validates :provider, presence: true, uniqueness: true
  scope :enabled, -> { where(enabled: true) }
end
```

- [ ] **Step 4: Implement UserSetting**

```ruby
# app/models/user_setting.rb
class UserSetting < ApplicationRecord
  belongs_to :user
  validates :theme, presence: true
end
```

- [ ] **Step 5: Implement ApiToken with secret-generation factory**

```ruby
# app/models/api_token.rb
class ApiToken < ApplicationRecord
  include Eventable
  belongs_to :user, default: -> { Current.user }
  has_secure_password :token, validations: false  # uses :token_digest

  def self.create_with_secret!(user:, name:, scopes: [])
    raw_secret = SecureRandom.hex(16)
    prefix     = SecureRandom.alphanumeric(8).downcase
    token      = create!(user:, name:, scopes:, prefix:, token: raw_secret)
    [token, "#{prefix}.#{raw_secret}"]
  end

  def self.authenticate(presented)
    prefix, secret = presented.to_s.split(".", 2)
    return nil if prefix.blank? || secret.blank?
    token = find_by(prefix: prefix)
    token&.authenticate_token(secret) || nil
  end
end
```

(`has_secure_password :token, validations: false` is Rails 8's generalized has_secure_password; it gives us `token_digest` + `authenticate_token`.)

- [ ] **Step 6: Add fixtures**

`test/fixtures/provider_configs.yml`:
```yaml
anthropic:
  provider: anthropic
  base_url: https://api.anthropic.com
  api_key: <%= Rails.application.message_verifier(:active_record_encrypted_attribute).generate("test-anthropic-key") rescue "test-anthropic-key" %>
  default_model: claude-opus-4-7
  enabled: true
```

`test/fixtures/user_settings.yml`:
```yaml
one:
  user: one
  theme: claude-official
  accent: indigo
  editor_font_size: 13
  notifications_enabled: true
  usage_threshold: 80
```

(`api_tokens.yml` is empty; tokens are created in tests via the factory.)

- [ ] **Step 7: Write + run tests**

```ruby
# test/models/provider_config_test.rb
test "api_key encrypts at rest" do
  ProviderConfig.create!(provider: "test", base_url: "https://x", api_key: "shh", default_model: "m", enabled: true)
  row = ActiveRecord::Base.connection.execute("SELECT api_key FROM provider_configs WHERE provider='test'").first
  refute_includes row.fetch("api_key").to_s, "shh"
end

# test/models/api_token_test.rb
test "create_with_secret returns plaintext only once" do
  token, raw = ApiToken.create_with_secret!(user: users(:one), name: "cli")
  assert_includes raw, "."
  assert ApiToken.authenticate(raw)
  refute ApiToken.authenticate(raw + "x")
end
```

Run: `bin/rails test test/models/provider_config_test.rb test/models/api_token_test.rb test/models/user_setting_test.rb`
Expected: 0 failures.

- [ ] **Step 8: Commit**

```bash
git add db config app test
git commit -m "Phase 1: ProviderConfig (encrypted), UserSetting, ApiToken (bcrypt token)"
```

#### Task 1.7: ChatSession + Message + ToolCall migrations & models

**Files:**
- Create: 5 migrations + 3 models + 4 concerns + 5 fixtures + tests

- [ ] **Step 1: Generate migrations**

```bash
bin/rails generate migration CreateChatSessions user:references title:string model:string provider:string forked_from:references{null} share_token:string:uniq last_active_at:datetime
bin/rails generate migration CreateMessages chat_session:references role:integer content_blocks:json stream_cursor:json status:integer prompt_tokens:integer completion_tokens:integer cache_read_tokens:integer cache_creation_tokens:integer cost_usd:decimal model:string provider:string error_message:text
bin/rails generate migration CreateToolCalls message:references provider_tool_id:string name:string source:integer input:json output:json status:integer error_message:text started_at:datetime finished_at:datetime
bin/rails generate migration CreateChatSessionArchives chat_session:references user:references
bin/rails generate migration CreateChatSessionPins chat_session:references user:references
```

Edit migrations:
- `cost_usd` precision: `t.decimal :cost_usd, precision: 12, scale: 6`.
- Add `t.index :share_token, unique: true, where: "share_token IS NOT NULL"` (partial unique).
- `chat_session_archives` and `chat_session_pins`: add `t.index [:chat_session_id, :user_id], unique: true`.

Run: `bin/rails db:migrate`
Expected: 5 tables.

- [ ] **Step 2: ChatSession model**

```ruby
# app/models/chat_session.rb
class ChatSession < ApplicationRecord
  include Eventable, ChatSession::Archivable, ChatSession::Pinnable, ChatSession::Forkable

  belongs_to :user, default: -> { Current.user }
  belongs_to :forked_from, class_name: "ChatSession", optional: true
  has_many :messages, -> { order(:created_at) }, dependent: :destroy
  has_many :forks, class_name: "ChatSession", foreign_key: :forked_from_id, dependent: :nullify

  before_create { self.last_active_at ||= Time.current }

  scope :active,        -> { where.missing(:archive) }
  scope :pinned_first,  -> { left_joins(:pin).order(Arel.sql("chat_session_pins.id IS NULL"), last_active_at: :desc) }
end
```

- [ ] **Step 3: State-record models + concerns**

```ruby
# app/models/chat_session/archive.rb
class ChatSession::Archive < ApplicationRecord
  self.table_name = "chat_session_archives"
  belongs_to :chat_session
  belongs_to :user, default: -> { Current.user }
end
```

```ruby
# app/models/chat_session/archivable.rb
module ChatSession::Archivable
  extend ActiveSupport::Concern
  included do
    has_one :archive, class_name: "ChatSession::Archive", dependent: :destroy
    scope :archived,   -> { joins(:archive) }
    scope :unarchived, -> { where.missing(:archive) }
  end

  def archived? = archive.present?
  def unarchived? = !archived?

  def archive(user: Current.user)
    unless archived?
      transaction do
        create_archive!(user: user)
        track_event :archived, creator: user
      end
    end
  end

  def unarchive(user: Current.user)
    if archived?
      transaction do
        archive.destroy
        track_event :unarchived, creator: user
      end
    end
  end
end
```

Mirror for `Pin` / `Pinnable` (POST/DELETE on `resource :pin`).

```ruby
# app/models/chat_session/forkable.rb
module ChatSession::Forkable
  extend ActiveSupport::Concern

  def fork(at: messages.last, user: Current.user)
    transaction do
      child = user.chat_sessions.create!(title: "#{title} (fork)", model:, provider:, forked_from: self)
      messages.where("created_at <= ?", at.created_at).each do |m|
        child.messages.create!(role: m.role, content_blocks: m.content_blocks, status: :completed, model: m.model, provider: m.provider)
      end
      track_event :forked, particulars: { child_id: child.id, at_message_id: at.id }
      child
    end
  end
end
```

- [ ] **Step 4: Message model**

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  include Eventable, Message::Streamable, Message::Costable, Message::Forkable

  belongs_to :chat_session
  has_many :tool_calls, dependent: :destroy

  enum :role,   system: 0, user: 1, assistant: 2, tool: 3
  enum :status, pending: 0, streaming: 1, completed: 2, failed: 3, rate_limited: 4, cancelled: 5

  scope :streaming,  -> { where(status: :streaming) }
  scope :done,       -> { where(status: %i[completed failed cancelled]) }
  scope :ordered,    -> { order(:created_at) }

  before_validation { self.content_blocks ||= [] }
end
```

Concerns get stubs at this task; `Message::Streamable#advance!` is filled in Task 1.9. Stub:

```ruby
# app/models/message/streamable.rb
module Message::Streamable
  extend ActiveSupport::Concern
  def advance!; raise NotImplementedError, "implemented in Task 1.9"; end
  def advance_later; Message::AdvanceJob.perform_later(self); end
end

# app/models/message/costable.rb
module Message::Costable
  extend ActiveSupport::Concern
  # Cost computation kicks in Phase 1.9; until then, just attribute readers.
end
```

- [ ] **Step 5: ToolCall model + stub Executable**

```ruby
# app/models/tool_call.rb
class ToolCall < ApplicationRecord
  include Eventable, ToolCall::Executable

  belongs_to :message
  has_many_attached :artifacts

  enum :source, internal: 0, mcp: 1, skill: 2
  enum :status, pending: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4
end

# app/models/tool_call/executable.rb
module ToolCall::Executable
  extend ActiveSupport::Concern
  def execute; raise NotImplementedError, "implemented in Phase 3"; end
end
```

- [ ] **Step 6: Fixtures**

`test/fixtures/chat_sessions.yml`:
```yaml
one:
  user: one
  title: "First chat"
  model: claude-opus-4-7
  provider: anthropic
  last_active_at: <%= Time.current.iso8601 %>
```

`test/fixtures/messages.yml`:
```yaml
hello:
  chat_session: one
  role: 1   # user
  content_blocks: <%= [{type: "text", text: "Hello"}].to_json %>
  status: 2  # completed
```

- [ ] **Step 7: Tests**

```ruby
# test/models/chat_session_test.rb
test "active scope excludes archived" do
  s = chat_sessions(:one)
  s.archive
  refute_includes ChatSession.active, s
end

test "fork copies messages up through cursor" do
  s = chat_sessions(:one)
  s.messages.create!(role: :assistant, content_blocks: [{type:"text", text:"Hi"}], status: :completed)
  child = s.fork(at: s.messages.last)
  assert_equal s.messages.count, child.messages.count
  assert_equal s, child.forked_from
end
```

Run: `bin/rails test test/models/chat_session_test.rb test/models/message_test.rb test/models/tool_call_test.rb`
Expected: 0 failures.

- [ ] **Step 8: Commit**

```bash
git add db app test
git commit -m "Phase 1: ChatSession + Message + ToolCall models with archive/pin/fork concerns"
```

#### Task 1.8: `Llm::Adapter` + `Llm::Anthropic` (real provider call)

**Files:**
- Modify: `Gemfile`, `test/test_helper.rb`
- Create: `app/services/llm/adapter.rb`, `app/services/llm/client.rb`, `app/services/llm/anthropic.rb`, `app/services/llm/retry_wrapper.rb`, `app/services/llm/message_normalizer.rb`, `test/services/llm/anthropic_test.rb`, `test/fixtures/vcr/anthropic_streaming.yml`

- [ ] **Step 1: Add VCR + WebMock**

Append to the `group :test do` block in `Gemfile`:

```ruby
gem "vcr", "~> 6.3"
gem "webmock", "~> 3.23"
```

Run: `bundle install`

- [ ] **Step 2: Wire VCR in test_helper**

`test/test_helper.rb` (append before the final `end`):

```ruby
require "webmock/minitest"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr"
  config.hook_into :webmock
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] || "test-key" }
  config.default_cassette_options = { record: :new_episodes, match_requests_on: %i[method uri] }
end
```

- [ ] **Step 3: Implement `Llm::Adapter` and `Llm::Client`** per § 7.1.

```ruby
# app/services/llm/adapter.rb
module Llm::Adapter
  def stream(messages:, tools:, model:, &block) = raise(NotImplementedError)
  def ping = raise(NotImplementedError)
end

# app/services/llm/client.rb
module Llm::Client
  module_function
  def for(provider:)
    config = ProviderConfig.find_by!(provider: provider)
    case provider
    when "anthropic" then Llm::Anthropic.new(config)
    when "openai"    then Llm::OpenAi.new(config)
    when "ollama"    then Llm::Ollama.new(config)
    else raise ArgumentError, "unknown provider #{provider.inspect}"
    end
  end
end

# app/services/llm/rate_limited.rb
class Llm::RateLimited < StandardError
  attr_reader :retry_after
  def initialize(retry_after:, message: nil) = (super(message || "rate limited"); @retry_after = retry_after)
end
```

- [ ] **Step 4: Implement `Llm::Anthropic`**

```ruby
# app/services/llm/anthropic.rb
class Llm::Anthropic
  include Llm::Adapter
  def initialize(config)
    @client = Anthropic::Client.new(api_key: config.api_key, base_url: (config.base_url.presence || "https://api.anthropic.com"))
  end

  def stream(messages:, tools:, model:, &block)
    raw = @client.messages.stream(
      model: model,
      max_tokens: 8_192,
      messages: messages,
      tools: tools.presence,
    )
    raw.each { |event| block.call(normalize(event)) }
    final = raw.message
    {
      prompt_tokens:         final.usage.input_tokens,
      completion_tokens:     final.usage.output_tokens,
      cache_read_tokens:     final.usage.cache_read_input_tokens || 0,
      cache_creation_tokens: final.usage.cache_creation_input_tokens || 0,
      finish_reason:         final.stop_reason,
    }
  rescue Anthropic::Errors::RateLimitError => e
    raise Llm::RateLimited.new(retry_after: e.response&.headers&.dig("retry-after").to_i.nonzero? || 30, message: e.message)
  end

  def ping
    @client.messages.create(model: "claude-haiku-4-5", max_tokens: 1, messages: [{ role: "user", content: "ping" }])
    true
  rescue => e
    raise Llm::PingFailed, e.message
  end

  private
    def normalize(event)
      case event
      when Anthropic::Models::MessageStartEvent       then { type: :message_start, message_id: event.message.id, model: event.message.model }
      when Anthropic::Models::ContentBlockStartEvent  then { type: :content_block_start, index: event.index, block: event.content_block.to_h }
      when Anthropic::Models::ContentBlockDeltaEvent  then normalize_delta(event)
      when Anthropic::Models::ContentBlockStopEvent   then { type: :content_block_stop, index: event.index }
      when Anthropic::Models::MessageDeltaEvent       then { type: :message_delta, finish_reason: event.delta.stop_reason }
      when Anthropic::Models::MessageStopEvent        then { type: :message_stop, finish_reason: nil }
      else { type: :unknown, raw: event.to_h }
      end
    end

    def normalize_delta(event)
      case event.delta
      when Anthropic::Models::TextDelta       then { type: :text_delta,             index: event.index, text: event.delta.text }
      when Anthropic::Models::ThinkingDelta   then { type: :thinking_delta,         index: event.index, thinking: event.delta.thinking }
      when Anthropic::Models::InputJsonDelta  then { type: :tool_use_input_delta,   index: event.index, partial_json: event.delta.partial_json }
      else { type: :delta_unknown, raw: event.to_h }
      end
    end
end
```

(SDK class names above are the ones in `anthropic ~> 1.41` — verify with `Anthropic::Models.constants` when running; if names differ, adapt the case branches accordingly.)

- [ ] **Step 5: Implement `Llm::OpenAi` and `Llm::Ollama` skeleton stubs**

Both implement `stream` via Faraday SSE; in Phase 1 they raise `NotImplementedError` if `provider_config.api_key` is unset and a TODO comment points to Phase 7. Wired into `Llm::Client.for` so the class exists.

- [ ] **Step 6: Record VCR cassette**

```bash
mkdir -p test/fixtures/vcr
ANTHROPIC_API_KEY=sk-ant-… bin/rails test test/services/llm/anthropic_test.rb
```

Cassette file `test/fixtures/vcr/anthropic_streaming.yml` lands in repo. Subsequent runs replay without making real HTTP calls.

The test:

```ruby
# test/services/llm/anthropic_test.rb
require "test_helper"
class Llm::AnthropicTest < ActiveSupport::TestCase
  test "streams a complete turn" do
    VCR.use_cassette("anthropic_streaming") do
      adapter = Llm::Anthropic.new(provider_configs(:anthropic))
      events  = []
      usage   = adapter.stream(messages: [{role:"user", content:"Say hi."}], tools: [], model: "claude-haiku-4-5") { |e| events << e }
      assert_includes events.map { _1[:type] }, :text_delta
      assert_predicate usage[:completion_tokens], :positive?
    end
  end
end
```

Run: `bin/rails test test/services/llm/anthropic_test.rb`
Expected: 1 run, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock app/services test/services test/fixtures/vcr test/test_helper.rb
git commit -m "Phase 1: Llm::Client + Anthropic adapter with VCR-backed streaming test"
```

#### Task 1.9: `Message#advance!` end-to-end (THE foundational task)

**Files:**
- Modify: `app/models/message/streamable.rb`, `app/models/message.rb`
- Create: `test/models/message/streamable_test.rb`

This task replaces the stub from Task 1.7 with the real streaming engine. Phase 1's whole purpose hinges on this working.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/message/streamable_test.rb
require "test_helper"
class Message::StreamableTest < ActiveSupport::TestCase
  test "advance! streams a complete turn and persists tokens" do
    VCR.use_cassette("anthropic_streaming") do
      session   = chat_sessions(:one)
      session.messages.create!(role: :user, content_blocks: [{ type: "text", text: "hi" }], status: :completed)
      assistant = session.messages.create!(role: :assistant, status: :pending, model: session.model, provider: "anthropic")
      assistant.advance!
      assert_equal "completed", assistant.reload.status
      assert_predicate assistant.completion_tokens, :positive?
      assert_predicate assistant.content_blocks.size, :positive?
      assert_equal "text", assistant.content_blocks.first["type"]
    end
  end

  test "advance! marks status rate_limited and reschedules" do
    session   = chat_sessions(:one)
    assistant = session.messages.create!(role: :assistant, status: :pending, model: session.model, provider: "anthropic")
    Llm::Anthropic.any_instance.stubs(:stream).raises(Llm::RateLimited.new(retry_after: 5, message: "slow down"))
    assert_enqueued_with(job: Message::AdvanceJob) { assistant.advance! }
    assert_equal "rate_limited", assistant.reload.status
  end
end
```

Run: `bin/rails test test/models/message/streamable_test.rb`
Expected: FAIL (`NotImplementedError: implemented in Task 1.9`).

- [ ] **Step 2: Implement `Message::Streamable#advance!` and helpers**

```ruby
# app/models/message/streamable.rb
module Message::Streamable
  extend ActiveSupport::Concern

  def advance!
    transition_to_streaming!

    usage = Llm::Client.for(provider: provider).stream(messages: prompt_messages, tools: available_tools, model: model) do |event|
      apply_stream_event!(event)
      broadcast_event(event)
    end

    if needs_tool_loop?
      run_tool_calls!
      advance!
    else
      finalize!(usage)
    end
  rescue Llm::RateLimited => e
    update!(status: :rate_limited, error_message: e.message)
    Message::AdvanceJob.set(wait: e.retry_after.seconds).perform_later(self)
  rescue => e
    update!(status: :failed, error_message: e.message)
    track_event :failed, error_class: e.class.name, error_message: e.message
    raise
  end

  def advance_later
    Message::AdvanceJob.perform_later(self)
  end

  private
    def transition_to_streaming!
      transaction do
        update!(status: :streaming) unless streaming?
        self.content_blocks ||= []
        self.stream_cursor = { "block_index" => -1, "byte_offset" => 0, "last_event_at" => Time.current.iso8601 }
      end
    end

    def apply_stream_event!(event)
      case event[:type]
      when :content_block_start
        content_blocks[event[:index]] = event[:block].deep_stringify_keys
      when :text_delta
        block = content_blocks[event[:index]] ||= { "type" => "text", "text" => "" }
        block["text"] = block["text"].to_s + event[:text]
      when :thinking_delta
        block = content_blocks[event[:index]] ||= { "type" => "thinking", "thinking" => "" }
        block["thinking"] = block["thinking"].to_s + event[:thinking]
      when :tool_use_input_delta
        block = content_blocks[event[:index]] ||= { "type" => "tool_use", "input_partial" => "" }
        block["input_partial"] = block["input_partial"].to_s + event[:partial_json]
      when :content_block_stop
        finalize_block!(event[:index])
      end
      self.stream_cursor = { "block_index" => event[:index] || stream_cursor.to_h["block_index"], "byte_offset" => 0, "last_event_at" => Time.current.iso8601 }
      save!
    end

    def finalize_block!(index)
      block = content_blocks[index]
      return unless block.is_a?(Hash) && block["type"] == "tool_use" && block["input_partial"]
      block["input"] = JSON.parse(block["input_partial"])
      block.delete("input_partial")
      ToolCall.find_or_create_by!(message: self, provider_tool_id: block["id"]) do |tc|
        tc.name   = block["name"]
        tc.source = infer_source(block["name"])
        tc.input  = block["input"]
        tc.status = :pending
      end
    end

    def infer_source(name)
      return :internal if Tool::Internal.lookup(name)
      return :mcp      if McpTool.exists?(name: name)
      :skill
    end

    def broadcast_event(event)
      ChatChannel.broadcast_to(chat_session, event)
    end

    def prompt_messages
      chat_session.messages.ordered.where("messages.id <= ?", id).map do |m|
        { role: m.role, content: m.content_blocks }
      end
    end

    def available_tools
      enabled_skills.flat_map(&:tool_definitions) +
        chat_session.user.mcp_servers.where(status: :reachable).flat_map { |s| s.mcp_tools.map(&:to_anthropic_tool_def) } +
        Tool::Internal.all_definitions
    end

    def enabled_skills
      Skill.joins(:enablements).where(skill_enablements: { user_id: chat_session.user_id })
    end

    def needs_tool_loop?
      content_blocks.any? { |b| b["type"] == "tool_use" && tool_calls.where(provider_tool_id: b["id"]).where.not(status: :succeeded).exists? }
    end

    def run_tool_calls!
      tool_calls.where(status: :pending).find_each do |tc|
        tc.execute  # in Phase 1 this raises NotImplementedError — see Phase 3 wiring
      end
      # After execution, append tool_result blocks for each succeeded call:
      tool_calls.where(status: :succeeded).find_each do |tc|
        next if content_blocks.any? { |b| b["type"] == "tool_result" && b["tool_use_id"] == tc.provider_tool_id }
        self.content_blocks << { "type" => "tool_result", "tool_use_id" => tc.provider_tool_id, "content" => tc.output.to_s, "is_error" => false }
      end
      save!
    end

    def finalize!(usage)
      self.prompt_tokens         = usage[:prompt_tokens]
      self.completion_tokens     = usage[:completion_tokens]
      self.cache_read_tokens     = usage[:cache_read_tokens]
      self.cache_creation_tokens = usage[:cache_creation_tokens]
      self.cost_usd              = compute_cost
      self.status                = :completed
      transaction do
        save!
        track_event :completed, finish_reason: usage[:finish_reason]
      end
    end

    def compute_cost
      # Pricing table lives in `Llm::Pricing` — Phase 1 implements Anthropic only.
      Llm::Pricing.compute(provider: provider, model: model,
        prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
        cache_read_tokens: cache_read_tokens, cache_creation_tokens: cache_creation_tokens)
    rescue Llm::Pricing::UnknownModel
      0
    end
end
```

Plus `app/services/llm/pricing.rb`:

```ruby
module Llm::Pricing
  class UnknownModel < StandardError; end
  TABLE = {
    "anthropic" => {
      "claude-opus-4-7"   => { input: 15.0,  output: 75.0,  cache_read: 1.5,  cache_write: 18.75 },
      "claude-sonnet-4-6" => { input:  3.0,  output: 15.0,  cache_read: 0.3,  cache_write:  3.75 },
      "claude-haiku-4-5"  => { input:  1.0,  output:  5.0,  cache_read: 0.1,  cache_write:  1.25 },
    },
  }.freeze

  module_function
  def compute(provider:, model:, prompt_tokens:, completion_tokens:, cache_read_tokens: 0, cache_creation_tokens: 0)
    p = TABLE.dig(provider, model) or raise UnknownModel, "#{provider}/#{model}"
    ((prompt_tokens || 0) * p[:input] +
     (completion_tokens || 0) * p[:output] +
     (cache_read_tokens || 0) * p[:cache_read] +
     (cache_creation_tokens || 0) * p[:cache_write]) / 1_000_000.0
  end
end
```

- [ ] **Step 3: Run test, pass**

Run: `bin/rails test test/models/message/streamable_test.rb`
Expected: 2 runs, 0 failures (the first uses the VCR cassette from Task 1.8; the second uses a stub to simulate rate-limit).

- [ ] **Step 4: Note about Phase 1 tool loop**

Phase 1's `run_tool_calls!` will raise `NotImplementedError` from `ToolCall::Executable#execute` if the LLM actually emits a `tool_use`. For Phase 1, ensure tests use prompts that don't trigger tools (the cassette in Task 1.8 is a plain "Say hi"). Phase 3 replaces the executable stub.

- [ ] **Step 5: Commit**

```bash
git add app/models/message app/services/llm/pricing.rb test/models/message
git commit -m "Phase 1: Message#advance! streaming engine with cost tracking"
```

#### Task 1.10: ChatChannel + Stimulus controller + chat UI

**Files:**
- Create: `app/channels/application_cable/connection.rb`, `app/channels/application_cable/channel.rb`, `app/channels/chat_channel.rb`
- Create: `app/controllers/chat_sessions_controller.rb`, `app/controllers/chat_sessions/messages_controller.rb`, `app/controllers/concerns/chat_session_scoped.rb`
- Create: views under `app/views/chat_sessions/`
- Create: `app/javascript/controllers/chat_controller.js`
- Create: `test/channels/chat_channel_test.rb`, `test/system/streaming_chat_test.rb`

- [ ] **Step 1: ApplicationCable::Connection** per § 8 (copy the snippet verbatim).

- [ ] **Step 2: ChatChannel**

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat_session = current_user.chat_sessions.find(params[:chat_session_id])
    stream_for chat_session
  end
end
```

- [ ] **Step 3: ChatSessionScoped controller concern**

```ruby
# app/controllers/concerns/chat_session_scoped.rb
module ChatSessionScoped
  extend ActiveSupport::Concern
  included { before_action :set_chat_session }
  private
    def set_chat_session
      @chat_session = Current.user.chat_sessions.find(params[:chat_session_id] || params[:id])
    end
end
```

- [ ] **Step 4: Controllers**

```ruby
# app/controllers/chat_sessions_controller.rb
class ChatSessionsController < ApplicationController
  def index
    @chat_sessions = Current.user.chat_sessions.active.pinned_first
  end

  def show
    @chat_session = Current.user.chat_sessions.find(params[:id])
  end

  def new
    @chat_session = Current.user.chat_sessions.build(
      title: "New chat",
      model: ENV.fetch("MOP_DEFAULT_MODEL", "claude-opus-4-7"),
      provider: "anthropic",
    )
  end

  def create
    @chat_session = Current.user.chat_sessions.create!(chat_session_params)
    redirect_to @chat_session
  end

  private
    def chat_session_params = params.require(:chat_session).permit(:title, :model, :provider)
end
```

```ruby
# app/controllers/chat_sessions/messages_controller.rb
class ChatSessions::MessagesController < ApplicationController
  include ChatSessionScoped

  def create
    @user_message      = @chat_session.messages.create!(role: :user,      content_blocks: [{ type: "text", text: params.require(:content) }], status: :completed)
    @assistant_message = @chat_session.messages.create!(role: :assistant, content_blocks: [], status: :pending, model: @chat_session.model, provider: @chat_session.provider)
    @assistant_message.advance_later
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat_session }
    end
  end
end
```

- [ ] **Step 5: Views**

`app/views/chat_sessions/show.html.erb`:
```erb
<%= turbo_stream_from @chat_session %>
<section data-controller="chat" data-chat-chat-session-id-value="<%= @chat_session.id %>">
  <header><h1><%= @chat_session.title %></h1></header>
  <div id="<%= dom_id(@chat_session, :messages) %>" class="messages">
    <%= render @chat_session.messages.ordered %>
  </div>
  <%= form_with url: chat_session_messages_path(@chat_session), local: false do |f| %>
    <%= f.text_area :content, rows: 3, required: true %>
    <%= f.submit "Send" %>
  <% end %>
</section>
```

`app/views/messages/_message.html.erb`:
```erb
<article id="<%= dom_id(message) %>" class="message message--<%= message.role %> message--<%= message.status %>">
  <% message.content_blocks.to_a.each_with_index do |block, i| %>
    <%= render partial: "messages/block_#{block['type'] || block[:type]}", locals: { block: block, index: i } %>
  <% end %>
</article>
```

Partials per block type: `_block_text.html.erb`, `_block_thinking.html.erb`, `_block_tool_use.html.erb`, `_block_tool_result.html.erb`. Each renders the relevant fields.

`app/views/chat_sessions/messages/create.turbo_stream.erb`:
```erb
<%= turbo_stream.append "#{dom_id(@chat_session, :messages)}", partial: "messages/message", locals: { message: @user_message } %>
<%= turbo_stream.append "#{dom_id(@chat_session, :messages)}", partial: "messages/message", locals: { message: @assistant_message } %>
```

- [ ] **Step 6: Stimulus controller**

```js
// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static values = { chatSessionId: Number }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "ChatChannel", chat_session_id: this.chatSessionIdValue },
      { received: (event) => this.dispatchEvent(event) }
    )
  }

  disconnect() { this.subscription?.unsubscribe() }

  dispatchEvent(event) {
    switch (event.type) {
      case "text_delta":     return this.appendText(event)
      case "thinking_delta": return this.appendThinking(event)
      case "content_block_start": return this.beginBlock(event)
      case "content_block_stop":  return this.endBlock(event)
      case "tool_use_input_delta": return this.appendToolInput(event)
      case "message_stop": return this.finalize(event)
      case "error": return this.showError(event)
    }
  }

  appendText({ index, text }) {
    const target = this.element.querySelector(`[data-block-index="${index}"][data-block-type="text"]`)
    if (target) target.textContent += text
  }
  appendThinking({ index, thinking }) {
    const target = this.element.querySelector(`[data-block-index="${index}"][data-block-type="thinking"]`)
    if (target) target.textContent += thinking
  }
  beginBlock({ index, block }) {
    const messagesEl = this.element.querySelector(`.message--streaming, .message--pending`)
    if (!messagesEl) return
    const el = document.createElement("div")
    el.dataset.blockIndex = index
    el.dataset.blockType = block.type
    el.className = `block block--${block.type}`
    if (block.type === "tool_use") el.dataset.toolName = block.name
    messagesEl.appendChild(el)
  }
  endBlock(_) { /* nothing for now */ }
  appendToolInput({ index, partial_json }) {
    const el = this.element.querySelector(`[data-block-index="${index}"][data-block-type="tool_use"]`)
    if (el) el.dataset.input = (el.dataset.input ?? "") + partial_json
  }
  finalize(_) {
    const streaming = this.element.querySelector(".message--streaming")
    streaming?.classList.replace("message--streaming", "message--completed")
  }
  showError({ message }) {
    const banner = document.createElement("p")
    banner.className = "chat-error"
    banner.textContent = message
    this.element.appendChild(banner)
  }
}
```

(The `consumer.js` file is the Rails 8 default — the `cable_ready` / Action Cable consumer Importmap pin already exists from the scaffold; verify with `cat app/javascript/channels/consumer.js`.)

- [ ] **Step 7: Channel test**

```ruby
# test/channels/chat_channel_test.rb
require "test_helper"
class ChatChannelTest < ActionCable::Channel::TestCase
  test "subscribes a user to their own session" do
    stub_connection current_user: users(:one)
    subscribe chat_session_id: chat_sessions(:one).id
    assert subscription.confirmed?
    assert_has_stream_for chat_sessions(:one)
  end
end
```

- [ ] **Step 8: System test (uses VCR cassette from Task 1.8)**

```ruby
# test/system/streaming_chat_test.rb
require "application_system_test_case"
class StreamingChatTest < ApplicationSystemTestCase
  test "sends a message and sees streaming response" do
    VCR.use_cassette("anthropic_streaming") do
      sign_in users(:one)
      visit chat_session_path(chat_sessions(:one))
      fill_in "Content", with: "Say hi."
      click_button "Send"
      assert_text "Hi", wait: 10
    end
  end
end
```

(`sign_in` helper in `test/application_system_test_case.rb` posts to `session_path`.)

- [ ] **Step 9: Run + commit**

Run: `bin/rails test test/channels test/system/streaming_chat_test.rb`
Expected: 0 failures.

```bash
git add app test
git commit -m "Phase 1: ChatChannel + chat UI with Stimulus controller and Turbo Streams"
```

#### Task 1.11: `Message::AdvanceJob` + ActiveJob `Current.user` extension

**Files:**
- Create: `config/initializers/active_job.rb`, `app/jobs/message/advance_job.rb`, `test/jobs/message/advance_job_test.rb`

- [ ] **Step 1: Create the initializer** per § 10.1 (copy verbatim).

- [ ] **Step 2: Create the job**

```ruby
# app/jobs/message/advance_job.rb
class Message::AdvanceJob < ApplicationJob
  queue_as :default
  def perform(message) = message.advance!
end
```

- [ ] **Step 3: Test enqueue + Current capture**

```ruby
# test/jobs/message/advance_job_test.rb
require "test_helper"
class Message::AdvanceJobTest < ActiveJob::TestCase
  test "advance_later enqueues" do
    message = messages(:hello)
    assert_enqueued_with(job: Message::AdvanceJob, args: [message]) do
      message.advance_later
    end
  end

  test "Current.user round-trips" do
    user = users(:one)
    Current.user = user
    job = Message::AdvanceJob.new(messages(:hello))
    payload = job.serialize
    new_job = Message::AdvanceJob.deserialize(payload)
    assert_equal user.id, new_job.captured_user.id
  end
end
```

Run: `bin/rails test test/jobs`
Expected: 0 failures.

- [ ] **Step 4: Commit**

```bash
git add config/initializers/active_job.rb app/jobs test/jobs
git commit -m "Phase 1: ActiveJob Current.user capture + Message::AdvanceJob"
```

#### Task 1.12: Settings → Providers page

**Files:**
- Create: `app/controllers/settings_controller.rb`, `app/controllers/settings/providers_controller.rb`, `app/controllers/settings/providers/tests_controller.rb`
- Create: views under `app/views/settings/`
- Create: `test/system/settings_provider_test.rb`

- [ ] **Step 1: Settings root**

```ruby
class SettingsController < ApplicationController
  def show; end
  def update
    Current.user.user_setting.update!(user_setting_params)
    redirect_to settings_path, notice: "Saved."
  end
  private
    def user_setting_params = params.require(:user_setting).permit(:theme, :accent, :editor_font_size, :sidebar_collapsed, :notifications_enabled, :usage_threshold)
end
```

- [ ] **Step 2: Providers index + show + update**

```ruby
class Settings::ProvidersController < ApplicationController
  before_action :set_provider, only: %i[show update]
  def index = (@providers = ProviderConfig.order(:provider))
  def show = nil
  def update
    @provider.update!(provider_params)
    redirect_to settings_provider_path(@provider), notice: "Saved."
  end
  private
    def set_provider = (@provider = ProviderConfig.find(params[:id]))
    def provider_params = params.require(:provider_config).permit(:api_key, :base_url, :default_model, :enabled)
end
```

- [ ] **Step 3: Test connection controller**

```ruby
class Settings::Providers::TestsController < ApplicationController
  def create
    provider = ProviderConfig.find(params[:provider_id])
    Llm::Client.for(provider: provider.provider).ping
    provider.update!(enabled: true) unless provider.enabled?
    redirect_to settings_provider_path(provider), notice: "Connection OK."
  rescue => e
    redirect_to settings_provider_path(params[:provider_id]), alert: "Failed: #{e.message}"
  end
end
```

- [ ] **Step 4: Views** — basic forms; theme selector dropdown on `settings/show.html.erb`.

- [ ] **Step 5: System test**

```ruby
# test/system/settings_provider_test.rb
require "application_system_test_case"
class SettingsProviderTest < ApplicationSystemTestCase
  test "tests provider connection" do
    VCR.use_cassette("anthropic_ping") do
      sign_in users(:one)
      visit settings_provider_path(provider_configs(:anthropic))
      click_button "Test connection"
      assert_text "Connection OK"
    end
  end
end
```

Run: `bin/rails test:system test/system/settings_provider_test.rb`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app test
git commit -m "Phase 1: Settings + Providers UI with connection test"
```

#### Task 1.13: Procfile.dev + bin/dev + bin/agents_supervisor stub

**Files:**
- Create: `Procfile.dev`, `bin/dev`, `bin/agents_supervisor`

- [ ] **Step 1: Procfile.dev**

```
web:        bin/rails server -p 3000
worker:     bin/rails solid_queue:start --recurring
supervisor: bin/agents_supervisor
```

- [ ] **Step 2: bin/dev**

```bash
#!/usr/bin/env bash
set -e
if ! gem list -i foreman >/dev/null 2>&1; then gem install foreman; fi
exec foreman start -f Procfile.dev "$@"
```

```bash
chmod +x bin/dev
```

- [ ] **Step 3: bin/agents_supervisor (Phase-1 stub)**

```ruby
#!/usr/bin/env ruby
require_relative "../config/environment"
require "socket"
require "json"

socket_path = Rails.root.join("tmp/sockets/agents_supervisor.sock")
FileUtils.mkdir_p(socket_path.dirname)
File.delete(socket_path) if File.exist?(socket_path)

server = UNIXServer.new(socket_path.to_s)
Rails.logger.info("[agents_supervisor] listening on #{socket_path}")

trap("TERM") { server.close; File.unlink(socket_path) rescue nil; exit }
trap("INT")  { server.close; File.unlink(socket_path) rescue nil; exit }

loop do
  client = server.accept
  Thread.new(client) do |c|
    c.each_line do |line|
      request = JSON.parse(line) rescue { "id" => nil, "method" => "parse_error" }
      response = case request["method"]
                 when "health.ping" then { jsonrpc: "2.0", id: request["id"], result: { pong: true, pid: Process.pid } }
                 else { jsonrpc: "2.0", id: request["id"], error: { code: -32601, message: "method not found in Phase 1: #{request["method"]}" } }
                 end
      c.puts(response.to_json)
    end
  ensure
    c&.close
  end
end
```

```bash
chmod +x bin/agents_supervisor
```

- [ ] **Step 4: Smoke check**

```bash
bin/dev
# In another shell:
curl -s -X POST -d '{"jsonrpc":"2.0","id":1,"method":"health.ping"}' --unix-socket tmp/sockets/agents_supervisor.sock http://x/  # if curl supports unix sockets
# Otherwise:
ruby -rsocket -rjson -e 'UNIXSocket.open("tmp/sockets/agents_supervisor.sock"){|s| s.puts({jsonrpc:"2.0",id:1,method:"health.ping"}.to_json); puts s.gets}'
```

Expected output:
```
{"jsonrpc":"2.0","id":1,"result":{"pong":true,"pid":…}}
```

Open http://localhost:3000, sign in, create a chat session, type "Hello", click Send. Tokens stream in.

- [ ] **Step 5: Commit**

```bash
git add Procfile.dev bin/dev bin/agents_supervisor
git commit -m "Phase 1: Procfile.dev + bin/dev + agents_supervisor stub with health.ping"
```

#### Phase 1 exit criteria + verification

- [ ] User signs in.
- [ ] Creates a chat session, streams a multi-turn conversation with Anthropic.
- [ ] Content blocks render with thinking accordion (basic).
- [ ] Costs tracked per message.
- [ ] Conversation persists across restarts.
- [ ] All tests pass:
  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```
  Expected for each: zero failures, no high-severity findings.

---

### Phase 2 — Memory + Files + Theme switcher (~1-2 weeks)

**Adds:**
- Migrations: `memory_files` (on `primary`), `memory_files_fts` virtual table (on `content`).
- `MemoryFile` concerns: `Reindexable` (`reindex!` + `MemoryFile.reindex_all` walks `${MOP_HOME}/memory/**/*.md`), `Writable` (`write(content)` atomically: write tmp → fsync → rename → enqueue indexer), `Searchable` (scope `matching(query)` joins through FTS5 table with `bm25()` ranking).
- `Memory::IndexerJob` triggered from `bin/agents_supervisor`'s `listen` watcher.
- Memory page (`/memory` → `MemoryController#show` lists tree, `/memory/files/*path` shows + edits). Editor: textarea + preview (Monaco upgrade in Phase 4).
- `WorkspacePath` value object + tests for traversal probes.
- `WorkspaceFile.tree(root:, max_depth: 3, max_entries: 20_000, ignore: %w[node_modules .git .next .turbo .cache __pycache__ .venv dist])`.
- Files page (`/files` + `Files::NodesController` for tree/show/update). Textarea editor.
- `theme_controller.js` writes `data-theme`/`data-accent` to `<html>`. Theme settings UI in `/settings`.
- `bin/agents_supervisor` v1: `listen` watcher for `${MOP_HOME}/memory/`, enqueues `Memory::IndexerJob` via its UNIX socket → Puma → ActiveJob.

**Per-phase task list to write before starting:** `docs/plans/phase-2-memory-files-themes.md`.

**Exit criteria:** Edit memory markdown in browser, persists to disk, full-text search returns snippets, file browser lists workspace tree with traversal guard, theme switch works.

---

### Phase 3 — Built-in tools + Skills (~2 weeks)

**Adds:**
- Migrations: `skills`, `skill_installations`, `skill_enablements`, `agent_profile_skills`.
- `Skill::Loadable` (`Skill.reload_from_disk`, `Skill#load_from_path!`) parses SKILL.md frontmatter per § 4.5.
- `Skill::SecurityAnalyzable`: returns `Skill::SecurityAnalysis` PORO with heuristic flags (shell-command mention, network call, file writes); upgrades `security_level` from frontmatter.
- `Skill::Installable` (`install_for(user)` / `uninstall_for(user)`) writes `SkillInstallation`. Required for `security_level >= medium`.
- `Skill::Enableable` (`enable_for(user)` / `disable_for(user)`) writes `SkillEnablement`. Enabled skills inject prompt sections.
- Built-in tools as a class-method registry on `Tool::Internal`:
  ```ruby
  class Tool::Internal
    def self.register(name, klass); registry[name] = klass; end
    def self.lookup(name); registry[name]; end
    private_class_method def self.registry; @registry ||= {}; end
  end
  Tool::Internal.register("read_file",  Tool::Internal::ReadFile)
  Tool::Internal.register("write_file", Tool::Internal::WriteFile)
  Tool::Internal.register("list_dir",   Tool::Internal::ListDir)
  Tool::Internal.register("run_shell",  Tool::Internal::RunShell)
  ```
  Each tool class has `def self.input_schema; …; end` and `def self.invoke(input:, user:); …; end`.
- `ToolCall::Executable#execute` looks up by source (`:internal` → `Tool::Internal.lookup(name).invoke`), records timestamps, writes `track_event :invoked` then `:succeeded` / `:failed`.
- Wire `tool_call.execute` into `Message#advance!`'s tool loop.
- Skills page (`/skills`) with categories, search, install/enable buttons, security badge.
- Seed data: `db/seeds/skills/` directory copied into `${MOP_HOME}/skills/` on first boot; ~5 builtin skills (filesystem, web_search stub, code_review, deep_research, summarize).

**Exit criteria:** Chat reads/writes files via tool calls; skill registry shows 5+ builtins; enabling a skill changes the system prompt; dangerous skills require explicit `SkillInstallation` acceptance.

---

### Phase 4 — MCP + Terminal + Supervisor v2 (~2-3 weeks)

**Adds:**
- Migrations: `mcp_servers`, `mcp_tools`, `terminal_sessions`.
- `bin/agents_supervisor` v2: tmux session lifecycle + MCP stdio bridge. Full JSON-RPC API per § 11.2.
- `Mcp::HttpClient`, `Mcp::StdioBridge`, `Mcp::DiscoveryJob`, `mcp_server.discover_tools!`, `mcp_tool.invoke(input)`.
- MCP page: list/create/edit/test servers, view discovered tools.
- `Terminal::TmuxManager` calling out to `tmux` CLI; `Terminal::StreamPump` reads from `pipe-pane` FIFO into `TerminalChannel.broadcast_to`.
- `Terminal::SweepJob` kills sessions past detach TTL (default 1 hour).
- Terminal page with xterm.js + `terminal_controller.js`.
- Upgrade memory + file editors to Monaco (importmap pin + lazy load per § 13.1).

**Exit criteria:** Configure an HTTP MCP server (e.g. context7) and call its tools from chat. Open a terminal, run commands, disconnect, reattach within TTL window with scrollback intact.

---

### Phase 5 — Scheduled Jobs + Dashboard (~1-2 weeks)

**Adds:**
- Migrations: `scheduled_jobs`, `job_runs`, `scheduled_job_pauses`.
- `SchedulerTickJob` parses cron with `fugit`, calls `ScheduledJob.run_all_due` which enqueues `ScheduledJob::RunnerJob` per due job.
- `ScheduledJob#run!` spins up a chat session, sends the prompt, captures output into a `JobRun`.
- Jobs page (`/jobs`): create cron-scheduled prompts, list runs, view output, pause/resume via `resource :pause`.
- Dashboard: aggregates from `Message`/`ToolCall`/`JobRun`/`McpServer.status`. Charts via chart.js. Token/cost rollups grouped by day, by session, by model.
- "Incidents" surface via `Event.where("action LIKE 'error_%'")` or an explicit `Event.incidents` scope.

**Exit criteria:** Schedule a daily prompt, see it run, view output, see costs and incidents on dashboard.

---

### Phase 6 — Swarm + Conductor + Agent Profiles (~3-4 weeks)

**Adds:**
- Migrations: `swarm_missions`, `swarm_assignments`, `swarm_checkpoints`, `swarm_events`, `agent_profiles`, `agent_profile_skills`, `swarm_mission_cancellations`.
- Agent profile seed file `db/seeds/agent_profiles.yml` mirroring upstream `swarm.yaml`.
- `AgentProfile` page (per-worker config). Roster page.
- `SwarmMission::Decomposable#decompose!` calls `Llm::Client.for(...)` with the orchestrator prompt template (`app/services/conductor/prompts.rb` → `decomposition.erb`).
- `SwarmAssignment.dispatch_ready` (class method) finds assignments whose `depends_on` is satisfied and dispatches via supervisor.
- `Swarm::OrchestratorLoopJob` (recurring 30s, 3-line wrapper) → `SwarmMission.advance_all_active`.
- `SwarmCheckpoint.parse(raw)` parses checkpoint markers from worker output.
- `bin/agents_supervisor` v3: per-profile tmux session for each swarm worker.
- Swarm pages: missions list, mission detail, kanban board, worker chat, mission events log.
- Auto/manual mode toggle.

**State machines:** see § 4.4. Transitions are explicit methods (`mission.dispatch!`, `mission.advance!`, `assignment.block!(reason)`).

**Exit criteria:** Spawn 2 swarm workers, give conductor a goal, watch decomposition, workers execute in tmux, kanban updates live, checkpoints record progress, blocked tasks await user input.

---

### Phase 7 — Polish + OpenAI compatibility (~1-2 weeks)

**Adds:**
- `Api::V1::ResponsesController` + `LlmResponsesAdapter` per § 14.
- `Api::V1::ChatCompletionsController` (legacy).
- API token UI (`/settings/api_tokens`, create/revoke, scopes).
- OAuth device-code flow at `/settings/oauth_device_code` (for Nous Portal-style external auth) — minimal, deferrable.
- Command palette (Stimulus + `cmdk` pin).
- PWA manifest + service worker (uncomment routes, refine asset list).
- Kamal deploy: Procfile parity (web + worker + supervisor as accessory), secrets via `config/credentials.yml.enc`, multi-DB volume mounts.
- Local provider discovery (Ollama probing at `http://localhost:11434`).
- Conversation export (markdown + JSON), session forking UI hookup.
- Rack::Attack throttles for `/v1/*` and `/session`.

**Exit criteria:** External client posts to `/v1/responses` with bearer token and gets streaming SSE back. App installable as PWA. Kamal deploy works end-to-end.

## 17. Verification

Per-phase test strategy (Rails default Minitest):

- **Model tests** for every concern (`Message::Streamable`, `Skill::Installable`, `ScheduledJob::Pausable`, `SwarmMission::Cancellable`, `ToolCall::Executable`, …) — fast, isolated, no HTTP. **Always set `Current.session = sessions(:one)` in `setup`** so lambda defaults resolve (`patterns-and-best-practices.md §7.3` gotcha #1; our `test_helper.rb` does this automatically).
- **System tests** (Capybara + Selenium) for each user-visible flow (sign in, send chat, edit memory, install skill, run scheduled job, dispatch swarm).
- **Channel tests** (`ActionCable::Channel::TestCase`) for Chat/Terminal/Swarm streams.
- **Adapter tests** for `Llm::*`, `Mcp::HttpClient`, `Mcp::StdioBridge`, `Terminal::TmuxManager`. Mock external HTTP via `WebMock`; record real Anthropic streaming once with `vcr` and replay.
- **Job tests**: assert enqueue via `assert_enqueued_with(job: Message::AdvanceJob)`; test the sync logic separately on the model. Both halves of `_now`/`_later` covered (`§4.4`).
- **Security tests**: path-traversal probes against `WorkspacePath` and `MemoryFile#write`; encrypted column round-trip; CSRF + bearer-auth boundaries; remote-bind boot check (`config/initializers/security_boot_check.rb`).
- **Event-tracking assertions**: every action method test asserts a corresponding `Event` row with the right `action` and `particulars` (`§3.1` recipe).
- **End-to-end smoke** at each phase exit: `bin/dev` boots; manual click-through covers the phase's exit criteria.

Run before declaring a phase done:

```bash
bin/rails db:migrate db:test:prepare
bin/rails test
bin/rails test:system
bin/bundle exec brakeman -A
bin/bundle exec bundler-audit check --update
```

Expected output for each: zero failures, no high-severity findings.

## 18. Critical files map (Phase 1 baseline)

Scaffold files modified in Phase 1:

- `Gemfile` — add `anthropic`, `faraday`, `fugit`, `bcrypt`, `listen`, `vcr`, `webmock`. (CSS is pure custom — no framework gem.)
- `config/database.yml` — multi-DB across all environments (§ 4.3).
- `config/cable.yml` — stays `async` for dev, `solid_cable` for production (already configured).
- `config/recurring.yml` — see § 10.
- `config/routes.rb` — full route map (§ 9).
- `config/application.rb` — `config.autoload_lib(ignore: %w[assets tasks])`, set `Rails.application.config.x.mop_home = ENV.fetch("MOP_HOME") { Rails.root.join("storage/workspace").to_s }`.
- `config/initializers/active_job.rb` — `Current.user` capture (§ 10.1).
- `config/initializers/content_security_policy.rb` — § 15.7.
- `config/initializers/security_boot_check.rb` — § 15.4.
- `app/views/layouts/application.html.erb` — `data-theme` binding, Turbo + Stimulus tags, nav shell.
- `Procfile.dev` — § 11.3.
- `bin/dev` — Foreman wrapper.
- `bin/agents_supervisor` — Phase-1 stub (§ Task 1.13); grows in Phase 2 (memory watcher), Phase 4 (tmux + MCP).

Each subsequent phase adds its own migrations, models, controllers, channels, services, jobs, views, and Stimulus controllers. The plan keeps Phase 1's surface tiny so the streaming foundation is rock-solid before piling on features.

## 19. Open items (decide during execution, not now)

- Whether to keep textarea/`easymde` or jump to Monaco for memory editing in Phase 2 (small cost difference; Phase 4 has the Monaco work either way).
- Final theme palette tokens — design pass before Phase 1 ships polish.
- Whether `bin/agents_supervisor` stays one process or splits into `bin/memory_watcher` + `bin/agents_supervisor` (revisit at Phase 4 when supervisor first has real work).
- Cost data retention policy on `Message` (full history vs monthly rollup) — revisit when DB size is measurable.
- Whether to gem-pin Monaco (`monaco-editor-rails`) instead of CDN (Phase 4 decision).
- Whether to add `async` gem for the supervisor's IO multiplexing or stay on plain threads + `IO.select` (Phase 4 decision).
- Whether to extract a `mop-core` engine for the chat/streaming primitives so they could be reused (post-v1; not for v1).

---

## Self-review checklist (completed)

- [x] **Spec coverage** — every Hermes Workspace feature area (Chat, Memory, Files, Terminal, Skills, MCP, Jobs, Settings, Dashboard, Swarm, Conductor, Agent Profiles, Themes) is assigned to a phase. Explicit non-goals listed in § 1.1.
- [x] **Placeholders** — every "TBD"/"add appropriate" replaced with concrete schemas, signatures, or commands.
- [x] **Type consistency** — `Message::AdvanceJob` (not `ChatStreamJob`) used everywhere; `SkillInstallation`/`SkillEnablement` schema explicit; `Event` polymorphic (not `AuditEvent`).
- [x] **Routes valid** — no malformed `collection do resources …, module: …` blocks; `marketplace` flattened to top-level resource.
- [x] **Header present** — REQUIRED SUB-SKILL line at top.
- [x] **Phase 1 task structure** — bite-sized checkbox steps with code + commands + expected output + commit per task.
- [x] **Interfaces specified** — `Llm::Adapter`, event union, `bin/agents_supervisor` JSON-RPC, `Eventable`, `Current`, ActiveJob extension.
- [x] **SQLite-specific corrections** — `json` not `jsonb`; integer PKs not UUIDs; multi-DB extended to dev/test.
- [x] **Test fixture sketch** — `users.yml`, `sessions.yml`, `test_helper.rb` setup hook.
