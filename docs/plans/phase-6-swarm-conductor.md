# Phase 6 — Swarm + Conductor + Agent Profiles

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the conductor accepts a goal, decomposes it into assignments, and N swarm workers execute those assignments in their own tmux panes while the operator watches kanban + checkpoints update live.

**Architecture:** A `SwarmMission` is the unit of work; the conductor (`SwarmMission#decompose!`) calls Anthropic with the orchestrator prompt to produce a JSON plan of `SwarmAssignment` rows. Each assignment is dispatched to an `AgentProfile` worker — a long-running tmux session managed by `bin/agents_supervisor` v3 (extends the Phase 4 v2 supervisor with `swarm.spawn_worker`/`send_keys`/`close_worker` RPC). Workers run an interactive Claude Code-style loop and emit YAML-fenced **checkpoint markers** which the orchestrator (`Swarm::OrchestratorLoopJob`, recurring 30s) parses into `SwarmCheckpoint` rows and uses to advance assignment + mission state machines.

**Tech Stack:** Rails 8.1, Solid Queue (recurring), Action Cable (Turbo Streams), Stimulus (kanban drag/drop), `tmux` via `Open3` (defence-in-depth array form), `anthropic` SDK, Concern composition for state-machine transitions, the `chat_session_archives`-style child table pattern for cancellations.

**Parent plan:** [`docs/plans/workflows.md`](workflows.md) § Phase 6 (lines 3048–3066); domain model § 4.1 (117–144), § 4.2 (146–158), state machines § 4.4 (226–252); routes § 9 (605–612); supervisor § 11 (758–808); service layer § 5 (284–331).

**Predecessors:** Phase 5 closed at HEAD `5e7269a` ("Fix issues in phase 5 implementation."). Hardening gate H1–H12 + Task 5.18 (end-to-end system test) all landed. **Phase 5 is NOT yet tagged** — Task 6.0 below pins the tag before any new code lands. Earlier tags: `phase-2`, `phase-2-final`, `phase-3`, `phase-4`.

**Carry-overs into Phase 6:**

| Source | Carry-over | Landing task |
|---|---|---|
| Phase 3 (workflows.md:3061) | Per-user / per-skill / per-profile filter in `Message#available_tools`; replace the Phase 3 non-admin `run_shell` stop-gap and the empty `skill_tool_definitions` stub | Task 6.21 |
| Phase 4.5 (slipped) | MCP stdio bridge (`mcp.spawn`/`mcp.invoke`/`mcp.shutdown`) — workers may want stdio MCP tools | **Out of scope** — flagged in Phase 6.5 slip candidates; exit criteria use built-in tools only |
| Phase 5 (open items) | `Event.prune!` recurring sweeper for the monotonically growing audit table | Task 6.22 |
| Phase 5 (slip 5.5 #2) | Per-skill / per-agent-profile filtering inside `ScheduledJob#run!` — same machinery as 6.21 once `agent_profile_skills` exists | Task 6.21 covers this — `ScheduledJob#run!` calls `Message#available_tools` via `Message#advance!` |

**Out-of-scope for Phase 6 (mirror parent plan):**
- MCP stdio support for swarm workers — slipped to 6.5. Workers run built-in tools + HTTP MCP only.
- Multi-mission concurrency throttling — single mission at a time per user is fine for v1.
- Cost-budget auto-pause — Phase 7.
- Worker-to-worker communication beyond `depends_on` ordering — out of scope.
- Speech / voice block-resolution UI — Phase 7 (`voice_input_controller.js`).

**Exit criteria:** Task 6.23 — spawn 2 workers, conductor decomposes a goal, workers execute in tmux, kanban updates live, checkpoints parsed and stored, blocked assignment surfaces in UI awaiting user input.

---

## Task 6.0 — Phase 5 epilogue + Phase 6 baseline

Phase 5's H1–H12 + Task 5.18–5.19 all closed but no `phase-5` tag exists yet. Tag it before any new code, then pin the baseline counts so a Phase 6 regression doesn't get blamed on Phase 5's late commits.

- [ ] **Step 1: Confirm clean tree + identify Phase 5 closing commit.**

  ```bash
  git status
  git log --oneline | head -15
  git tag --list 'phase-*'
  ```

  Expected: working tree clean; HEAD `5e7269a` ("Fix issues in phase 5 implementation."); no `phase-5` tag yet (only `phase-2`, `phase-2-final`, `phase-3`, `phase-4`).

- [ ] **Step 2: Green baseline before tagging.**

  ```bash
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```

  Expected: tests green. Record the run/assertion counts to your scratchpad (Phase 5 Task 5.19 should have measured these; Phase 6 Task 6.24 compares against this baseline). Brakeman: count = Phase 5 final + 0 new (the only change is your scratchpad). Bundler-audit: 0 vulnerabilities.

- [ ] **Step 3: Tag `phase-5` at HEAD.**

  ```bash
  git tag phase-5
  git tag --list 'phase-*'
  ```

  Expected: `phase-5` now in the list. (Don't push tags without confirmation — local-only is fine for the baseline pin.)

- [ ] **Step 4: Extend the `users` fixture with a second non-admin user.** Phase 6 tests need a second tenant for cross-tenancy assertions. Today `test/fixtures/users.yml` ships `one` (role: 1 = admin) and `member` (role: 0). The Phase 6 plan references `users(:two)` and `users(:admin)` — alias them in-place so we don't have to rewrite every Phase 6 test:

  Edit `test/fixtures/users.yml` to add:

  ```yaml
  admin:    # alias for the admin user
    email: admin@example.test
    password_digest: <%= BCrypt::Password.create("supersecret123") %>
    role: 1
    single_user_bootstrap: false

  two:      # second non-admin tenant for cross-tenancy tests
    email: two@example.test
    password_digest: <%= BCrypt::Password.create("supersecret123") %>
    role: 0
    single_user_bootstrap: false
  ```

  Run `bin/rails test test/models/user_test.rb` to confirm no fixture conflicts.

- [ ] **Step 5: Commit.** Tag step + fixture addition is one commit:

  ```
  Phase 6 Task 6.0: tag phase-5 + add users(:admin) and users(:two) fixtures for Phase 6 cross-tenancy tests
  ```

---

## Test-helper conventions for Phase 6

Two project-specific patterns the rest of this plan uses heavily — read this once so the executor doesn't reinvent them.

**Singleton-method stubbing (instead of `mocha`).** The project's `Gemfile` does NOT include `mocha`. `test/support/method_stub.rb` ships a tiny shim:

```ruby
# Block form — replaces an instance/class method for the block's lifetime
with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(_assignment) {
  { tmux_session_name: "x", fifo: "/tmp/x" }
}) do
  asg.dispatch!
end

# Minitest-style form (also provided by the shim)
Swarm::TmuxBridge.stub(:spawn_worker, ->(_) { { tmux_session_name: "x", fifo: "/tmp/x" } }) do
  asg.dispatch!
end
```

When this plan writes `Swarm::TmuxBridge.expects(:spawn_worker).with(...)` (a mocha idiom), **substitute** `Swarm::TmuxBridge.stub(:spawn_worker, ->(arg) { ... })` and structure the assertion as "did `dispatch!` produce the expected DB state?" rather than "was the mock called with these args?". For tighter argument capture, use the block form and capture into a local variable.

**LLM stubbing.** `test/support/llm_stubs.rb` exports `LlmStubs.with_stubbed_llm(adapter)` and a `StubAdapter.new(text:)`. The Phase 6 plan introduces a wrapper `LlmStubs.with_decomposition(plan_or_string)` that compiles a plan hash into a JSON-fenced assistant reply and delegates to `with_stubbed_llm`. The wrapper definition lives in Task 6.9 Step 2.

---

## Task 6.1 — `agent_profiles` migration + `AgentProfile` model + YAML seed

`AgentProfile` is per-worker config: model/provider, role, specialties, where its tmux cwd starts. Seeded from `db/seeds/agent_profiles.yml` mirroring upstream Hermes' `swarm.yaml`. The model owns `enabled?`/`online?`/`away?`/`offline?` boolean queries and a `refresh_from_yaml!` class method.

**Files:**
- Create: `db/migrate/<ts>_create_agent_profiles.rb`
- Create: `app/models/agent_profile.rb`
- Create: `app/models/agent_profile/loadable.rb`
- Create: `db/seeds/agent_profiles.yml`
- Create: `test/fixtures/agent_profiles.yml`
- Create: `test/models/agent_profile_test.rb`
- Create: `test/models/agent_profile/loadable_test.rb`

- [ ] **Step 1: Write the failing migration + model tests.**

  `test/models/agent_profile_test.rb`:

  ```ruby
  require "test_helper"

  class AgentProfileTest < ActiveSupport::TestCase
    test "validates slug presence + uniqueness" do
      AgentProfile.create!(slug: "backend", display_name: "Backend Worker",
                           role: "backend-engineer", model: "claude-sonnet-4-5",
                           provider: "anthropic", cwd: "agents/backend")
      dup = AgentProfile.new(slug: "backend", display_name: "Dup",
                             role: "x", model: "claude-sonnet-4-5",
                             provider: "anthropic", cwd: "agents/dup")
      assert_not dup.valid?
      assert_includes dup.errors[:slug], "has already been taken"
    end

    test "status enum members + default" do
      profile = AgentProfile.new(slug: "p", display_name: "P", role: "r",
                                 model: "m", provider: "anthropic", cwd: "p")
      assert_equal "offline", profile.status
      assert_respond_to profile, :online?
      assert_respond_to profile, :away?
      assert_respond_to profile, :offline?
    end

    test "enabled scope and disabled scope partition" do
      enabled  = AgentProfile.create!(slug: "a", display_name: "A", role: "r",
                                      model: "m", provider: "anthropic",
                                      cwd: "a", enabled: true)
      disabled = AgentProfile.create!(slug: "b", display_name: "B", role: "r",
                                      model: "m", provider: "anthropic",
                                      cwd: "b", enabled: false)
      assert_includes AgentProfile.enabled,   enabled
      assert_includes AgentProfile.disabled,  disabled
      refute_includes AgentProfile.enabled,   disabled
    end
  end
  ```

- [ ] **Step 2: Run tests — expect failure.**

  ```
  bin/rails test test/models/agent_profile_test.rb
  ```

  Expected: `NameError: uninitialized constant AgentProfile` (and migration not yet present).

- [ ] **Step 3: Migration.**

  ```bash
  bin/rails g migration CreateAgentProfiles
  ```

  Contents:

  ```ruby
  class CreateAgentProfiles < ActiveRecord::Migration[8.1]
    def change
      create_table :agent_profiles do |t|
        t.string  :slug,         null: false
        t.string  :display_name, null: false
        t.string  :role,         null: false
        t.string  :model,        null: false
        t.string  :provider,     null: false
        t.json    :specialties,  default: [], null: false
        t.json    :avoid_tasks,  default: [], null: false
        t.string  :cwd,          null: false
        t.integer :status,       null: false, default: 2     # 0=online, 1=away, 2=offline
        t.boolean :enabled,      null: false, default: true
        t.string  :body_digest                                 # sha256 of YAML stanza body — used by Loadable
        t.timestamps
      end
      add_index :agent_profiles, :slug, unique: true
      add_index :agent_profiles, [ :enabled, :status ]
    end
  end
  ```

- [ ] **Step 4: Model + concern + seed.**

  `app/models/agent_profile.rb`:

  ```ruby
  class AgentProfile < ApplicationRecord
    include Eventable
    include Loadable

    has_many :agent_profile_skills, dependent: :destroy
    has_many :skills, through: :agent_profile_skills

    enum :status, { online: 0, away: 1, offline: 2 }

    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9][a-z0-9_-]{0,63}\z/ }
    validates :display_name, :role, :model, :provider, :cwd, presence: true

    scope :enabled,  -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :rostered, -> { enabled.order(:display_name) }
  end
  ```

  `app/models/agent_profile/loadable.rb`:

  ```ruby
  module AgentProfile::Loadable
    extend ActiveSupport::Concern

    class_methods do
      # Reads `db/seeds/agent_profiles.yml` and upserts each profile.
      # `body_digest` short-circuits unchanged rows so re-running the seed
      # is idempotent and event-free.
      def refresh_from_yaml!(path: Rails.root.join("db/seeds/agent_profiles.yml"))
        yaml = YAML.safe_load_file(path)
        Array(yaml["profiles"]).each do |entry|
          slug   = entry.fetch("slug")
          digest = Digest::SHA256.hexdigest(entry.to_yaml)
          profile = find_or_initialize_by(slug: slug)
          next if profile.persisted? && profile.body_digest == digest

          profile.assign_attributes(
            display_name: entry.fetch("display_name"),
            role:         entry.fetch("role"),
            model:        entry.fetch("model"),
            provider:     entry.fetch("provider"),
            specialties:  Array(entry["specialties"]),
            avoid_tasks:  Array(entry["avoid_tasks"]),
            cwd:          entry.fetch("cwd"),
            enabled:      entry.fetch("enabled", true),
            body_digest:  digest
          )
          profile.save!
          profile.track_event(profile.previously_new_record? ? :created : :updated)
        end
      end
    end
  end
  ```

  `db/seeds/agent_profiles.yml`:

  ```yaml
  profiles:
    - slug: backend
      display_name: Backend Worker
      role: backend-engineer
      model: claude-sonnet-4-5
      provider: anthropic
      specialties:
        - Rails
        - SQLite
        - background jobs
      avoid_tasks:
        - frontend styling
      cwd: agents/backend
      enabled: true

    - slug: frontend
      display_name: Frontend Worker
      role: frontend-engineer
      model: claude-sonnet-4-5
      provider: anthropic
      specialties:
        - Stimulus
        - Turbo Streams
        - CSS @layer
      avoid_tasks:
        - migrations
      cwd: agents/frontend
      enabled: true
  ```

  `test/fixtures/agent_profiles.yml`:

  ```yaml
  backend:
    slug: backend
    display_name: Backend Worker
    role: backend-engineer
    model: claude-sonnet-4-5
    provider: anthropic
    specialties: '["Rails"]'
    avoid_tasks: '[]'
    cwd: agents/backend
    status: 2
    enabled: true

  frontend:
    slug: frontend
    display_name: Frontend Worker
    role: frontend-engineer
    model: claude-sonnet-4-5
    provider: anthropic
    specialties: '["Stimulus"]'
    avoid_tasks: '[]'
    cwd: agents/frontend
    status: 2
    enabled: true
  ```

- [ ] **Step 5: Loadable test.**

  `test/models/agent_profile/loadable_test.rb`:

  ```ruby
  require "test_helper"

  class AgentProfile::LoadableTest < ActiveSupport::TestCase
    test "refresh_from_yaml! upserts each profile + tracks events" do
      Current.user = users(:one)
      AgentProfile.delete_all
      assert_difference -> { AgentProfile.count }, 2 do
        AgentProfile.refresh_from_yaml!
      end
      backend = AgentProfile.find_by!(slug: "backend")
      assert_equal "Backend Worker", backend.display_name
      assert_includes backend.specialties, "Rails"
      assert_predicate backend, :enabled?
    end

    test "refresh_from_yaml! is idempotent — second call writes no rows" do
      Current.user = users(:one)
      AgentProfile.delete_all
      AgentProfile.refresh_from_yaml!
      assert_no_difference -> { AgentProfile.count } do
        AgentProfile.refresh_from_yaml!
      end
      assert_no_difference -> { Event.where(action: "agent_profile_updated").count } do
        AgentProfile.refresh_from_yaml!
      end
    end
  end
  ```

- [ ] **Step 6: Migrate + run tests.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/agent_profile_test.rb test/models/agent_profile/loadable_test.rb
  ```

  Expected: green.

- [ ] **Step 7: Commit.**

  ```
  Phase 6 Task 6.1: agent_profiles migration + AgentProfile model + Loadable + YAML seed
  ```

---

## Task 6.2 — `agent_profile_skills` join + `AgentProfile.skills_for(user)`

The join links profiles to the global `skills` table and, transitively, to a user's enabled skills (a worker's tool kit = its profile's skills ∩ user's enabled skills).

**Files:**
- Create: `db/migrate/<ts>_create_agent_profile_skills.rb`
- Create: `app/models/agent_profile_skill.rb`
- Modify: `app/models/agent_profile.rb` (already declared `has_many :skills, through: :agent_profile_skills` in 6.1)
- Create: `test/fixtures/agent_profile_skills.yml`
- Create: `test/models/agent_profile_skill_test.rb`

- [ ] **Step 1: Failing test.**

  `test/models/agent_profile_skill_test.rb`:

  ```ruby
  require "test_helper"

  class AgentProfileSkillTest < ActiveSupport::TestCase
    test "join validates uniqueness on (agent_profile, skill)" do
      profile = agent_profiles(:backend)
      skill   = skills(:research)
      AgentProfileSkill.create!(agent_profile: profile, skill: skill)
      dup = AgentProfileSkill.new(agent_profile: profile, skill: skill)
      assert_not dup.valid?
    end

    test "AgentProfile.skills_for(user) intersects profile skills with user enablement" do
      Current.user = users(:one)
      profile = agent_profiles(:backend)
      research_skill = skills(:research)
      build_skill    = skills(:builder)
      profile.skills << research_skill << build_skill

      research_skill.install_for(users(:one))
      research_skill.enable_for(users(:one))
      # builder is installed/enabled for a DIFFERENT user
      build_skill.install_for(users(:two))
      build_skill.enable_for(users(:two))

      assigned = profile.skills_for(users(:one))
      assert_includes assigned, research_skill
      refute_includes assigned, build_skill
    end
  end
  ```

- [ ] **Step 2: Migration + model.**

  ```ruby
  class CreateAgentProfileSkills < ActiveRecord::Migration[8.1]
    def change
      create_table :agent_profile_skills do |t|
        t.references :agent_profile, null: false, foreign_key: true
        t.references :skill,         null: false, foreign_key: true
        t.timestamps
      end
      add_index :agent_profile_skills, [ :agent_profile_id, :skill_id ], unique: true
    end
  end
  ```

  `app/models/agent_profile_skill.rb`:

  ```ruby
  class AgentProfileSkill < ApplicationRecord
    belongs_to :agent_profile
    belongs_to :skill

    validates :skill_id, uniqueness: { scope: :agent_profile_id }
  end
  ```

  Add to `app/models/agent_profile.rb` (already in 6.1's draft, verify it's there) — and add the instance method:

  ```ruby
  def skills_for(user)
    skills.merge(Skill.enabled_for(user))
  end
  ```

  `test/fixtures/agent_profile_skills.yml` (start empty — tests build associations explicitly).

- [ ] **Step 3: Migrate + test.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/agent_profile_skill_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.2: agent_profile_skills join + AgentProfile#skills_for(user) intersection
  ```

---

## Task 6.3 — `swarm_missions` migration + `SwarmMission` skeleton

State machine column (`state` integer enum) + `mode` toggle (`auto`/`manual`). No transition methods yet — Tasks 6.9 / 6.15 / 6.17 add `decompose!`, `dispatch!`, `advance!`, `block!`, `cancel!` etc.

**Files:**
- Create: `db/migrate/<ts>_create_swarm_missions.rb`
- Create: `app/models/swarm_mission.rb`
- Create: `test/fixtures/swarm_missions.yml`
- Create: `test/models/swarm_mission_test.rb`

- [ ] **Step 1: Failing test.**

  `test/models/swarm_mission_test.rb`:

  ```ruby
  require "test_helper"

  class SwarmMissionTest < ActiveSupport::TestCase
    setup { Current.user = users(:one) }

    test "validates title + goal presence" do
      m = SwarmMission.new
      assert_not m.valid?
      assert_includes m.errors[:title], "can't be blank"
      assert_includes m.errors[:goal],  "can't be blank"
    end

    test "state enum default is :planning and mode default is :auto" do
      m = SwarmMission.create!(title: "X", goal: "Y")
      assert_equal "planning", m.state
      assert_equal "auto",     m.mode
      assert_predicate m, :planning?
      assert_predicate m, :auto?
    end

    test "active scope excludes :complete and :cancelled" do
      complete  = SwarmMission.create!(title: "C", goal: "G", state: :complete)
      cancelled = SwarmMission.create!(title: "X", goal: "G", state: :cancelled)
      executing = SwarmMission.create!(title: "E", goal: "G", state: :executing)
      assert_includes SwarmMission.active,    executing
      refute_includes SwarmMission.active,    complete
      refute_includes SwarmMission.active,    cancelled
    end

    test "default belongs_to :user resolves from Current.user" do
      m = SwarmMission.create!(title: "X", goal: "Y")
      assert_equal users(:one), m.user
      assert_equal users(:one), m.created_by
    end
  end
  ```

- [ ] **Step 2: Migration + model.**

  ```ruby
  class CreateSwarmMissions < ActiveRecord::Migration[8.1]
    def change
      create_table :swarm_missions do |t|
        t.references :user,       null: false, foreign_key: true
        t.references :created_by, null: false, foreign_key: { to_table: :users }
        t.string  :title, null: false
        t.text    :goal,  null: false
        t.integer :state, null: false, default: 0    # planning=0, dispatching=1, executing=2,
                                                     # reviewing=3, blocked=4, complete=5, cancelled=6
        t.integer :mode,  null: false, default: 0    # auto=0, manual=1
        t.text    :decomposition_notes
        t.timestamps
      end
      add_index :swarm_missions, [ :user_id, :state ]
    end
  end
  ```

  `app/models/swarm_mission.rb`:

  ```ruby
  class SwarmMission < ApplicationRecord
    include Eventable

    belongs_to :user,       default: -> { Current.user }
    belongs_to :created_by, class_name: "User", default: -> { Current.user }

    has_many :assignments, class_name: "SwarmAssignment",
                           inverse_of: :swarm_mission,
                           dependent: :destroy
    has_many :swarm_events, dependent: :destroy

    enum :state, { planning: 0, dispatching: 1, executing: 2, reviewing: 3,
                   blocked: 4, complete: 5, cancelled: 6 }
    enum :mode,  { auto: 0, manual: 1 }

    validates :title, presence: true
    validates :goal,  presence: true

    scope :active,    -> { where.not(state: %i[complete cancelled]) }
    scope :recent,    -> { order(created_at: :desc) }
    scope :for_user,  ->(u) { where(user: u) }
  end
  ```

  `test/fixtures/swarm_missions.yml`:

  ```yaml
  alpha:
    user:       one
    created_by: one
    title: "Alpha mission"
    goal:  "Build the X feature"
    state: 0
    mode:  0

  alpha_cancelled:
    user:       one
    created_by: one
    title: "Cancelled"
    goal:  "Was cancelled"
    state: 6
    mode:  0
  ```

- [ ] **Step 3: Migrate + run test.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/swarm_mission_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.3: swarm_missions migration + SwarmMission skeleton (Eventable + enums)
  ```

---

## Task 6.4 — `swarm_assignments` migration + `SwarmAssignment` skeleton

`depends_on:json` is an array of sibling `SwarmAssignment#id`s. `state` enum drives dispatch ordering. No transitions yet.

**Files:**
- Create: `db/migrate/<ts>_create_swarm_assignments.rb`
- Create: `app/models/swarm_assignment.rb`
- Create: `test/fixtures/swarm_assignments.yml`
- Create: `test/models/swarm_assignment_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmAssignmentTest < ActiveSupport::TestCase
    setup { Current.user = users(:one) }

    test "default state is :pending and review_required is false" do
      a = SwarmAssignment.create!(
        swarm_mission: swarm_missions(:alpha),
        agent_profile: agent_profiles(:backend),
        task: "Do the thing"
      )
      assert_equal "pending", a.state
      assert_equal false, a.review_required
      assert_equal [],    a.depends_on
    end

    test "ready scope = pending && depends_on satisfied" do
      mission = swarm_missions(:alpha)
      first = SwarmAssignment.create!(swarm_mission: mission,
                                      agent_profile: agent_profiles(:backend),
                                      task: "T1", state: :completed)
      ready = SwarmAssignment.create!(swarm_mission: mission,
                                      agent_profile: agent_profiles(:frontend),
                                      task: "T2", depends_on: [ first.id ])
      not_ready = SwarmAssignment.create!(swarm_mission: mission,
                                          agent_profile: agent_profiles(:frontend),
                                          task: "T3", depends_on: [ ready.id ])
      result = SwarmAssignment.ready
      assert_includes result, ready
      refute_includes result, not_ready
    end
  end
  ```

- [ ] **Step 2: Migration + model.**

  ```ruby
  class CreateSwarmAssignments < ActiveRecord::Migration[8.1]
    def change
      create_table :swarm_assignments do |t|
        t.references :swarm_mission, null: false, foreign_key: true
        t.references :agent_profile, null: false, foreign_key: true
        t.text    :task,             null: false
        t.text    :rationale
        t.json    :depends_on,       default: [],   null: false
        t.integer :state,            default: 0,    null: false
                  # pending=0, dispatched=1, running=2, completed=3,
                  # failed=4, blocked=5, cancelled=6
        t.boolean :review_required,  default: false, null: false
        t.string  :tmux_session_name             # set when dispatched
        t.text    :block_reason
        t.references :chat_session,  foreign_key: true
        t.datetime :dispatched_at
        t.datetime :finished_at
        t.timestamps
      end
      add_index :swarm_assignments, [ :swarm_mission_id, :state ]
    end
  end
  ```

  `app/models/swarm_assignment.rb`:

  ```ruby
  class SwarmAssignment < ApplicationRecord
    include Eventable

    belongs_to :swarm_mission, inverse_of: :assignments
    belongs_to :agent_profile
    belongs_to :chat_session, optional: true
    has_many   :checkpoints, class_name: "SwarmCheckpoint",
                             foreign_key: :swarm_assignment_id,
                             dependent: :destroy

    enum :state, { pending: 0, dispatched: 1, running: 2, completed: 3,
                   failed: 4, blocked: 5, cancelled: 6 }

    validates :task, presence: true

    scope :pending_state, -> { where(state: :pending) }
    scope :ready, -> {
      pending_completed_ids = where(state: :completed).pluck(:id).to_set
      pending_state.select do |a|
        Array(a.depends_on).all? { |id| pending_completed_ids.include?(id) }
      end
    }
    scope :live, -> { where(state: %i[dispatched running blocked]) }
    scope :resolved, -> { where(state: %i[completed failed cancelled]) }

    # No transition methods yet — Tasks 6.10, 6.14, 6.15 add dispatch!, advance!,
    # block!, unblock!, complete!, fail!, cancel!.
  end
  ```

  `test/fixtures/swarm_assignments.yml`:

  ```yaml
  alpha_t1:
    swarm_mission: alpha
    agent_profile: backend
    task: "Do thing 1"
    state: 0
    depends_on: '[]'

  alpha_t2:
    swarm_mission: alpha
    agent_profile: frontend
    task: "Do thing 2"
    state: 0
    depends_on: '[]'
  ```

- [ ] **Step 3: Migrate + test.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/swarm_assignment_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.4: swarm_assignments migration + SwarmAssignment skeleton
  ```

---

## Task 6.5 — `swarm_mission_cancellations` + `SwarmMission::Cancellable`

Child-table cancellation, parallel to `chat_session_archives` / `scheduled_job_pauses`. Per workflows.md:155, cancellation goes through a child table for non-repudiation (who cancelled, when).

**Files:**
- Create: `db/migrate/<ts>_create_swarm_mission_cancellations.rb`
- Create: `app/models/swarm_mission/cancellation.rb`
- Create: `app/models/swarm_mission/cancellable.rb`
- Modify: `app/models/swarm_mission.rb` (include `Cancellable`)
- Create: `test/fixtures/swarm_mission_cancellations.yml`
- Create: `test/models/swarm_mission/cancellable_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmMission::CancellableTest < ActiveSupport::TestCase
    setup { Current.user = users(:one) }

    test "cancel! creates child row + flips state + tracks event" do
      mission = swarm_missions(:alpha)
      assert_not mission.cancelled?
      assert_difference -> { Event.where(action: "swarm_mission_cancelled").count }, 1 do
        mission.cancel(reason: "demo", user: users(:one))
      end
      assert_predicate mission, :cancelled?
      assert_equal "demo", mission.cancel_record.reason
      assert_equal users(:one), mission.cancel_record.user
    end

    test "cancel! is idempotent" do
      mission = swarm_missions(:alpha)
      mission.cancel(reason: "first")
      assert_no_difference -> { SwarmMission::Cancellation.count } do
        mission.cancel(reason: "second")
      end
    end

    test "cancel! propagates to live assignments → :cancelled" do
      mission = swarm_missions(:alpha)
      a = SwarmAssignment.create!(swarm_mission: mission, agent_profile: agent_profiles(:backend),
                                  task: "Do", state: :running)
      mission.cancel
      assert_equal "cancelled", a.reload.state
    end
  end
  ```

- [ ] **Step 2: Migration + concern + child model.**

  ```ruby
  class CreateSwarmMissionCancellations < ActiveRecord::Migration[8.1]
    def change
      create_table :swarm_mission_cancellations do |t|
        t.references :swarm_mission, null: false, foreign_key: true, index: { unique: true }
        t.references :user,          null: false, foreign_key: true
        t.string :reason
        t.timestamps
      end
    end
  end
  ```

  `app/models/swarm_mission/cancellation.rb`:

  ```ruby
  class SwarmMission::Cancellation < ApplicationRecord
    self.table_name = "swarm_mission_cancellations"
    belongs_to :swarm_mission
    belongs_to :user, default: -> { Current.user }
  end
  ```

  `app/models/swarm_mission/cancellable.rb`:

  ```ruby
  module SwarmMission::Cancellable
    extend ActiveSupport::Concern

    included do
      has_one :cancel_record, class_name: "SwarmMission::Cancellation",
                              foreign_key: :swarm_mission_id,
                              dependent: :destroy
    end

    def cancelled_by_record?
      cancel_record.present?
    end

    def cancel(reason: nil, user: Current.user)
      return if cancelled?

      transaction do
        create_cancel_record!(user: user, reason: reason)
        update!(state: :cancelled)
        assignments.live.find_each { |a| a.update!(state: :cancelled) }
        track_event :cancelled, creator: user, reason: reason
      end
    end
  end
  ```

  Add `include Cancellable` to `app/models/swarm_mission.rb`.

  `test/fixtures/swarm_mission_cancellations.yml`:

  ```yaml
  alpha_cancelled:
    swarm_mission: alpha_cancelled
    user: one
    reason: demo
  ```

- [ ] **Step 3: Migrate + test.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/swarm_mission/cancellable_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.5: swarm_mission_cancellations + Cancellable concern + child Cancellation model
  ```

---

## Task 6.6 — `swarm_events` migration + `SwarmEvent` telemetry log

**Important distinction:** `SwarmEvent` is NOT the same as the audit `Event`. `Event` (Eventable) is low-volume audit trail; `SwarmEvent` is high-frequency worker telemetry (every checkpoint, every stdout flush of a notable line). They have different retention policies and don't share the polymorphic table.

**Files:**
- Create: `db/migrate/<ts>_create_swarm_events.rb`
- Create: `app/models/swarm_event.rb`
- Create: `test/fixtures/swarm_events.yml`
- Create: `test/models/swarm_event_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmEventTest < ActiveSupport::TestCase
    setup { Current.user = users(:one) }

    test "log! creates a row with occurred_at + sets defaults" do
      mission = swarm_missions(:alpha)
      ev = SwarmEvent.log!(mission: mission, kind: "decomposed", message: "5 assignments planned",
                           data: { assignment_count: 5 })
      assert_equal mission, ev.swarm_mission
      assert_in_delta Time.current.to_f, ev.occurred_at.to_f, 1.0
      assert_equal 5, ev.data["assignment_count"]
    end

    test ".recent orders by occurred_at descending" do
      mission = swarm_missions(:alpha)
      a = SwarmEvent.log!(mission: mission, kind: "k1", message: "first",  data: {}, occurred_at: 5.minutes.ago)
      b = SwarmEvent.log!(mission: mission, kind: "k2", message: "second", data: {})
      assert_equal [ b, a ], mission.swarm_events.recent.to_a.first(2)
    end
  end
  ```

- [ ] **Step 2: Migration + model.**

  ```ruby
  class CreateSwarmEvents < ActiveRecord::Migration[8.1]
    def change
      create_table :swarm_events do |t|
        t.references :swarm_mission,    null: false, foreign_key: true
        t.references :swarm_assignment, null: true,  foreign_key: true
        t.string   :kind,        null: false
        t.text     :message
        t.json     :data,        default: {},  null: false
        t.datetime :occurred_at, null: false
        t.timestamps
      end
      add_index :swarm_events, [ :swarm_mission_id, :occurred_at ]
    end
  end
  ```

  `app/models/swarm_event.rb`:

  ```ruby
  class SwarmEvent < ApplicationRecord
    belongs_to :swarm_mission
    belongs_to :swarm_assignment, optional: true

    scope :recent,         -> { order(occurred_at: :desc) }
    scope :since,          ->(t) { where("occurred_at >= ?", t).recent }
    scope :for_assignment, ->(a) { where(swarm_assignment_id: a.id) }
    scope :of_kind,        ->(*k) { where(kind: k) }

    # Append-only helper: do NOT use `Event` — this is telemetry, not audit.
    def self.log!(mission:, assignment: nil, kind:, message: nil, data: {}, occurred_at: Time.current)
      create!(swarm_mission: mission, swarm_assignment: assignment,
              kind: kind.to_s, message: message, data: data, occurred_at: occurred_at)
    end
  end
  ```

  `test/fixtures/swarm_events.yml`:

  ```yaml
  alpha_start:
    swarm_mission: alpha
    kind: started
    message: "Mission alpha started"
    data: '{}'
    occurred_at: <%= 1.hour.ago.utc.iso8601 %>
  ```

- [ ] **Step 3: Migrate + test.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/swarm_event_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.6: swarm_events telemetry log (distinct from Eventable audit table)
  ```

---

## Task 6.7 — `swarm_checkpoints` migration + `SwarmCheckpoint.parse(raw)`

A checkpoint is a parsed YAML stanza emitted between sentinels in worker output. The parser is the heart of the orchestrator's progress detection — get it right and robust against malformed input.

**Marker format (canonical):**

```
===HERMES CHECKPOINT===
state_label: implementing-authentication
runtime_state:
  step: 3
  total_steps: 7
files_changed:
  - app/controllers/sessions_controller.rb
  - app/models/session.rb
commands_run:
  - bin/rails test test/controllers/sessions_controller_test.rb
result: "Implemented login form and POST /session"
blocker: null
next_action: "Add CSRF token tests"
===END CHECKPOINT===
```

- `state_label`, `result`, `blocker`, `next_action` are strings (nullable for blocker/next_action).
- `runtime_state`, `files_changed`, `commands_run` are arbitrary nested YAML — stored as JSON.
- A `blocker:` non-null marker indicates the worker is blocked awaiting user input.

**Files:**
- Create: `db/migrate/<ts>_create_swarm_checkpoints.rb`
- Create: `app/models/swarm_checkpoint.rb`
- Create: `test/fixtures/swarm_checkpoints.yml`
- Create: `test/models/swarm_checkpoint_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmCheckpointTest < ActiveSupport::TestCase
    test ".parse extracts a single checkpoint stanza" do
      raw = <<~RAW
        Just some noise
        ===HERMES CHECKPOINT===
        state_label: planning
        runtime_state:
          step: 1
        files_changed: []
        commands_run: []
        result: "Sketched the API"
        blocker: null
        next_action: "Wire the controller"
        ===END CHECKPOINT===
        more noise
      RAW

      parsed = SwarmCheckpoint.parse(raw)
      assert_equal 1, parsed.size
      cp = parsed.first
      assert_equal "planning", cp[:state_label]
      assert_equal "Sketched the API", cp[:result]
      assert_nil cp[:blocker]
      assert_equal "Wire the controller", cp[:next_action]
      assert_equal({ "step" => 1 }, cp[:runtime_state])
    end

    test ".parse returns [] on no markers" do
      assert_equal [], SwarmCheckpoint.parse("nothing\nhere\n")
    end

    test ".parse skips malformed stanzas without raising" do
      raw = <<~RAW
        ===HERMES CHECKPOINT===
        not: yaml at all
          this is: { broken: [ ]
        ===END CHECKPOINT===
        ===HERMES CHECKPOINT===
        state_label: good
        runtime_state: {}
        files_changed: []
        commands_run: []
        result: "ok"
        blocker: null
        next_action: null
        ===END CHECKPOINT===
      RAW
      parsed = SwarmCheckpoint.parse(raw)
      assert_equal 1, parsed.size
      assert_equal "good", parsed.first[:state_label]
    end

    test ".parse detects blocker stanza" do
      raw = <<~RAW
        ===HERMES CHECKPOINT===
        state_label: stuck
        runtime_state: {}
        files_changed: []
        commands_run: []
        result: null
        blocker: "Need DB credentials"
        next_action: null
        ===END CHECKPOINT===
      RAW
      parsed = SwarmCheckpoint.parse(raw)
      assert_equal "Need DB credentials", parsed.first[:blocker]
    end
  end
  ```

- [ ] **Step 2: Migration + model.**

  ```ruby
  class CreateSwarmCheckpoints < ActiveRecord::Migration[8.1]
    def change
      create_table :swarm_checkpoints do |t|
        t.references :swarm_assignment, null: false, foreign_key: true
        t.string :state_label,          null: false
        t.json   :runtime_state,        default: {}, null: false
        t.json   :files_changed,        default: [], null: false
        t.json   :commands_run,         default: [], null: false
        t.text   :result
        t.text   :blocker
        t.text   :next_action
        t.text   :raw,                  null: false
        t.timestamps
      end
      add_index :swarm_checkpoints, [ :swarm_assignment_id, :created_at ]
    end
  end
  ```

  `app/models/swarm_checkpoint.rb`:

  ```ruby
  class SwarmCheckpoint < ApplicationRecord
    belongs_to :swarm_assignment

    MARKER_RE = /===HERMES CHECKPOINT===\n(.*?)\n===END CHECKPOINT===/m

    # Returns Array<Hash> with symbolised top-level keys. Malformed YAML stanzas
    # are skipped (logged at Rails.logger.warn) — never raise into the
    # orchestrator loop, which would halt the mission.
    def self.parse(raw)
      raw.to_s.scan(MARKER_RE).filter_map do |(body)|
        yaml = YAML.safe_load(body, permitted_classes: [], aliases: false)
        next unless yaml.is_a?(Hash) && yaml["state_label"].is_a?(String)

        {
          state_label:   yaml["state_label"],
          runtime_state: yaml["runtime_state"] || {},
          files_changed: Array(yaml["files_changed"]),
          commands_run:  Array(yaml["commands_run"]),
          result:        yaml["result"],
          blocker:       yaml["blocker"],
          next_action:   yaml["next_action"],
          raw:           "===HERMES CHECKPOINT===\n#{body}\n===END CHECKPOINT==="
        }
      rescue Psych::SyntaxError => e
        Rails.logger.warn("[SwarmCheckpoint] skipped malformed stanza: #{e.message}")
        nil
      end
    end
  end
  ```

  `test/fixtures/swarm_checkpoints.yml` — empty (each test constructs its own).

- [ ] **Step 3: Migrate + test.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/swarm_checkpoint_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.7: swarm_checkpoints table + SwarmCheckpoint.parse marker extractor
  ```

---

## Task 6.8 — `app/services/conductor/prompts.rb` + `decomposition.erb`

The conductor needs a prompt template that takes a mission + available agent profiles + each profile's skill kit, and asks the model for a structured decomposition. Stored as ERB on disk so non-devs can iterate.

**Files:**
- Create: `app/services/conductor.rb`
- Create: `app/services/conductor/prompts.rb`
- Create: `app/services/conductor/prompts/decomposition.erb`
- Create: `test/services/conductor/prompts_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class Conductor::PromptsTest < ActiveSupport::TestCase
    setup { Current.user = users(:one) }

    test "decomposition renders mission goal + profile list + skill list" do
      mission = swarm_missions(:alpha)
      profiles = AgentProfile.rostered.to_a
      rendered = Conductor::Prompts.decomposition(mission: mission, profiles: profiles, user: users(:one))
      assert_match(/Build the X feature/, rendered)
      assert_match(/Backend Worker/, rendered)
      assert_match(/Frontend Worker/, rendered)
      assert_match(/Return JSON with the following shape/, rendered)
    end

    test "decomposition is safe with zero rostered profiles" do
      assert_nothing_raised { Conductor::Prompts.decomposition(mission: swarm_missions(:alpha), profiles: [], user: users(:one)) }
    end
  end
  ```

- [ ] **Step 2: Module + template.**

  `app/services/conductor.rb`:

  ```ruby
  module Conductor
  end
  ```

  `app/services/conductor/prompts.rb`:

  ```ruby
  module Conductor
    module Prompts
      TEMPLATES_DIR = Pathname.new(__dir__).join("prompts")

      module_function

      def decomposition(mission:, profiles:, user:)
        render("decomposition.erb",
               mission:   mission,
               profiles:  profiles,
               user:      user)
      end

      def render(name, locals)
        template = ERB.new(TEMPLATES_DIR.join(name).read, trim_mode: "-")
        binding = TOPLEVEL_BINDING.dup
        locals.each { |k, v| binding.local_variable_set(k, v) }
        template.result(binding)
      end
    end
  end
  ```

  `app/services/conductor/prompts/decomposition.erb`:

  ```erb
  You are the conductor for a swarm of <%= profiles.size %> agent workers.

  ## Mission
  Title: <%= mission.title %>
  Goal:
  <%= mission.goal %>

  ## Available workers
  <% profiles.each do |p| -%>
  - slug: <%= p.slug %>
    display_name: <%= p.display_name %>
    role: <%= p.role %>
    specialties: <%= p.specialties.join(", ") %>
    avoid_tasks: <%= p.avoid_tasks.join(", ") %>
    enabled_skills:
  <% p.skills_for(user).each do |s| -%>
      - <%= s.slug %>: <%= s.description %>
  <% end -%>
  <% end -%>

  ## Your task
  Decompose the mission into 2–8 assignments. Each assignment goes to one worker.
  Use the worker's specialties to pick assignees. Avoid assigning tasks that
  match a worker's `avoid_tasks` list. Order matters — earlier assignments can
  be referenced as `depends_on`.

  Return JSON with the following shape, and ONLY this JSON, in a single fenced
  code block:

  ```json
  {
    "decomposition_notes": "1–3 sentences explaining your plan",
    "assignments": [
      {
        "agent_slug": "backend",
        "task": "Imperative description of the work",
        "rationale": "Why this worker, why this order",
        "depends_on": [],
        "review_required": false
      }
    ]
  }
  ```

  `depends_on` is a list of 1-based indices into the `assignments` array.
  ```

- [ ] **Step 3: Run test.**

  ```
  bin/rails test test/services/conductor/prompts_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.8: Conductor::Prompts + decomposition.erb template
  ```

---

## Task 6.9 — `SwarmMission::Decomposable#decompose!` + `Swarm::DecompositionJob`

`decompose!` opens a hidden ChatSession, posts the conductor prompt as the user message, runs `Message#advance!` synchronously (mirroring `ScheduledJob::Runnable#run_now`), parses the JSON envelope from the assistant's final text, and creates `SwarmAssignment` rows in a single transaction. Mission state transitions `planning → dispatching` on success; on failure (parse error or LLM error), an `Event` row of action `swarm_mission_decomposition_failed` is recorded and the state stays `:planning` (operator retries via UI).

**Files:**
- Create: `app/models/swarm_mission/decomposable.rb`
- Create: `app/jobs/swarm/decomposition_job.rb`
- Modify: `app/models/swarm_mission.rb` (include `Decomposable`)
- Modify: `test/support/llm_stubs.rb` (extend the Phase 5 stub helper for decomposition fixtures)
- Create: `test/models/swarm_mission/decomposable_test.rb`
- Create: `test/jobs/swarm/decomposition_job_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmMission::DecomposableTest < ActiveSupport::TestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
    end

    test "decompose! parses JSON envelope, creates assignments, flips state" do
      mission = swarm_missions(:alpha)
      assert_predicate mission, :planning?

      LlmStubs.with_decomposition({
        decomposition_notes: "Plan",
        assignments: [
          { agent_slug: "backend",  task: "T1", rationale: "R1", depends_on: [],     review_required: false },
          { agent_slug: "frontend", task: "T2", rationale: "R2", depends_on: [ 1 ],  review_required: true  }
        ]
      }) do
        assert_difference -> { SwarmAssignment.count }, 2 do
          mission.decompose!
        end
      end

      assert_predicate mission.reload, :dispatching?
      assert_equal "Plan", mission.decomposition_notes
      first, second = mission.assignments.order(:id).to_a
      assert_equal "backend",  first.agent_profile.slug
      assert_equal "frontend", second.agent_profile.slug
      assert_equal [ first.id ], second.depends_on
    end

    test "decompose! on bad JSON records failure event + keeps state :planning" do
      mission = swarm_missions(:alpha)
      LlmStubs.with_decomposition("not json at all") do
        assert_difference -> { mission.events.where(action: "swarm_mission_decomposition_failed").count }, 1 do
          assert_no_difference -> { SwarmAssignment.count } do
            mission.decompose!
          end
        end
      end
      assert_predicate mission.reload, :planning?
    end

    test "decompose! rejects unknown agent_slug with a clear error event" do
      mission = swarm_missions(:alpha)
      LlmStubs.with_decomposition({
        decomposition_notes: "Plan",
        assignments: [
          { agent_slug: "nonexistent", task: "T1", rationale: "R", depends_on: [], review_required: false }
        ]
      }) do
        mission.decompose!
      end
      assert_predicate mission.reload, :planning?
      ev = mission.events.where(action: "swarm_mission_decomposition_failed").last
      assert_match(/unknown agent_slug.*nonexistent/, ev.particulars["error"])
    end

    test "decompose! rejects depends_on cycles" do
      # 1 depends on 2; 2 depends on 1
      mission = swarm_missions(:alpha)
      LlmStubs.with_decomposition({
        decomposition_notes: "Bad plan",
        assignments: [
          { agent_slug: "backend",  task: "T1", rationale: "R", depends_on: [ 2 ], review_required: false },
          { agent_slug: "frontend", task: "T2", rationale: "R", depends_on: [ 1 ], review_required: false }
        ]
      }) do
        mission.decompose!
      end
      assert_predicate mission.reload, :planning?
    end
  end
  ```

- [ ] **Step 2: Implement `Decomposable`.**

  `app/models/swarm_mission/decomposable.rb`:

  ```ruby
  module SwarmMission::Decomposable
    extend ActiveSupport::Concern

    JSON_FENCE_RE = /```(?:json)?\s*\n(.*?)\n```/m

    def decompose!
      return unless planning?

      raw = run_conductor_turn
      plan = parse_plan(raw)
      validate_plan!(plan)

      transaction do
        plan["assignments"].each_with_index do |entry, idx|
          profile = AgentProfile.find_by!(slug: entry.fetch("agent_slug"))
          deps    = Array(entry["depends_on"]).map { |i| created_assignment_ids[i - 1] or raise "invalid depends_on index #{i}" }
          asg = assignments.create!(
            agent_profile:   profile,
            task:            entry.fetch("task"),
            rationale:       entry["rationale"],
            depends_on:      deps,
            review_required: entry.fetch("review_required", false)
          )
          created_assignment_ids << asg.id
        end
        update!(state: :dispatching, decomposition_notes: plan["decomposition_notes"])
        track_event :decomposed, count: plan["assignments"].size
      end
      SwarmEvent.log!(mission: self, kind: "decomposed", message: "Mission decomposed",
                      data: { count: plan["assignments"].size })
    rescue => e
      Rails.logger.warn("[SwarmMission#decompose!] #{e.class}: #{e.message}")
      track_event :decomposition_failed, error: e.message.first(255)
      SwarmEvent.log!(mission: self, kind: "decomposition_failed", message: e.message, data: {})
    end

    def decompose_later
      Swarm::DecompositionJob.perform_later(self)
    end

    private
      def created_assignment_ids
        @created_assignment_ids ||= []
      end

      def run_conductor_turn
        chat = ChatSession.create!(
          user: user, title: "Conductor decomposition: #{title}",
          model: AgentProfile.first&.model || "claude-sonnet-4-5",
          provider: AgentProfile.first&.provider || "anthropic",
          last_active_at: Time.current
        )
        prompt = Conductor::Prompts.decomposition(
          mission:  self,
          profiles: AgentProfile.rostered.to_a,
          user:     user
        )
        chat.messages.create!(role: :user, status: :completed,
                              content_blocks: [ { type: "text", text: prompt } ],
                              model: chat.model, provider: chat.provider)
        assistant = chat.messages.create!(role: :assistant, status: :pending,
                                          content_blocks: [],
                                          model: chat.model, provider: chat.provider)
        assistant.advance!
        Array(assistant.reload.content_blocks).filter_map { |b|
          b["text"] if b.is_a?(Hash) && b["type"] == "text"
        }.join("\n\n")
      end

      def parse_plan(raw)
        fenced = raw.to_s[JSON_FENCE_RE, 1] || raw.to_s
        JSON.parse(fenced)
      end

      def validate_plan!(plan)
        raise "missing 'assignments' key" unless plan.is_a?(Hash) && plan["assignments"].is_a?(Array)

        plan["assignments"].each_with_index do |entry, idx|
          raise "assignment #{idx + 1}: missing agent_slug" if entry["agent_slug"].blank?
          raise "assignment #{idx + 1}: missing task"        if entry["task"].blank?
          slug = entry["agent_slug"]
          unless AgentProfile.exists?(slug: slug, enabled: true)
            raise "unknown agent_slug '#{slug}'"
          end
          Array(entry["depends_on"]).each do |dep|
            unless dep.is_a?(Integer) && dep.between?(1, idx)
              raise "assignment #{idx + 1}: invalid depends_on #{dep.inspect} (must reference an earlier assignment)"
            end
          end
        end
      end
  end
  ```

  Add `include Decomposable` to `app/models/swarm_mission.rb`.

  `app/jobs/swarm/decomposition_job.rb`:

  ```ruby
  module Swarm
    class DecompositionJob < ApplicationJob
      def perform(mission) = mission.decompose!
    end
  end
  ```

  `test/support/llm_stubs.rb` — extend the existing helper (which exports `with_stubbed_llm(adapter)` + `StubAdapter.new(text:)`):

  ```ruby
  module LlmStubs
    # Wraps a decomposition plan into a JSON-fenced assistant reply and stubs
    # Llm::Client.for. If the caller passes a String, send it as-is (lets us
    # test malformed input).
    def with_decomposition(plan, &block)
      text = case plan
             when String then plan
             else "```json\n#{plan.to_json}\n```"
             end
      with_stubbed_llm(StubAdapter.new(text: text), &block)
    end
  end
  ```

  Confirm the test class includes `LlmStubs` (already done at the bottom of `test/support/llm_stubs.rb` via `ActiveSupport::TestCase.include(LlmStubs)`).

- [ ] **Step 3: Run tests.**

  ```
  bin/rails test test/models/swarm_mission/decomposable_test.rb
  bin/rails test test/jobs/swarm/decomposition_job_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.9: SwarmMission::Decomposable + DecompositionJob (LLM call → assignments + cycle/unknown-slug rejection)
  ```

---

## Task 6.10 — Supervisor v3: `swarm.*` RPC methods + `Swarm::TmuxBridge`

The supervisor needs three new methods that mirror the Phase 4 `terminal.*` family:

- `swarm.spawn_worker` — creates `mop-swarm-<assignment-id>` tmux session in the profile's cwd, opens a pipe-pane FIFO for output.
- `swarm.send_keys` — types into the worker's tmux pane (used to deliver block-resolution input).
- `swarm.close_worker` — kills the worker's tmux session.

Notification: `swarm.output` (server → client) — used by the Rails-side stream pump to broadcast to `SwarmChannel.stream_for(swarm_mission)`.

**Files:**
- Modify: `bin/agents_supervisor` (add `SwarmTmuxBridge` + register methods)
- Create: `app/services/swarm/tmux_bridge.rb`
- Modify: `app/services/agents_supervisor/client.rb` — already supports arbitrary `.call(method, params)` (Phase 4); no change.
- Create: `test/services/swarm/tmux_bridge_test.rb`
- Modify: `test/integration/supervisor_v2_test.rb` → rename to `supervisor_test.rb` if Phase 4 already covered the v2 surface, OR add a new `test/integration/supervisor_v3_test.rb` with swarm.* probes.

- [ ] **Step 1: Failing supervisor integration test.**

  `test/integration/supervisor_v3_test.rb`:

  ```ruby
  require "test_helper"
  require "open3"
  require "socket"

  class SupervisorV3Test < ActiveSupport::TestCase
    # Boots the supervisor on a sandboxed UNIX socket and exercises swarm.*
    # methods. Skips on CI if tmux isn't installed (matches Phase 4 pattern).

    setup do
      skip "tmux missing on this host" unless system("which tmux >/dev/null 2>&1")
      @socket = Dir::Tmpname.create("supervisor-v3.sock") { |p| p }
      env = ENV.to_h.merge("MOP_SUPERVISOR_SOCKET" => @socket)
      @stdin, @stdout_err, @wait = Open3.popen2e(env, Rails.root.join("bin/agents_supervisor").to_s)
      wait_for_socket(@socket)
    end

    teardown do
      Process.kill("TERM", @wait.pid) rescue nil
      @wait.join(5)
      File.unlink(@socket) if File.exist?(@socket)
    end

    test "swarm.spawn_worker creates a tmux session and returns name + fifo" do
      result = rpc("swarm.spawn_worker", assignment_id: 999, profile_slug: "test", cwd: Dir.tmpdir, cols: 100, rows: 30)
      assert_match(/\Amop-swarm-999\z/, result["tmux_session_name"])
      assert File.exist?(result["fifo"])
      rpc("swarm.close_worker", assignment_id: 999)
    end

    test "swarm.close_worker is idempotent" do
      rpc("swarm.spawn_worker", assignment_id: 998, profile_slug: "test", cwd: Dir.tmpdir, cols: 100, rows: 30)
      assert_nothing_raised { rpc("swarm.close_worker", assignment_id: 998) }
      assert_nothing_raised { rpc("swarm.close_worker", assignment_id: 998) }
    end

    private
      def rpc(method, **params)
        sock = UNIXSocket.open(@socket)
        sock.write({ jsonrpc: "2.0", id: SecureRandom.hex(4), method: method, params: params }.to_json + "\n")
        JSON.parse(sock.gets).fetch("result")
      ensure
        sock&.close
      end

      def wait_for_socket(path)
        20.times { return if File.exist?(path); sleep 0.1 }
        raise "supervisor socket never appeared at #{path}"
      end
  end
  ```

- [ ] **Step 2: Add `SwarmTmuxBridge` to `bin/agents_supervisor`.**

  After the existing `AgentsSupervisor::TmuxBridge` class, add:

  ```ruby
  module AgentsSupervisor
    # Owns the tmux side of swarm workers. Mirrors TmuxBridge but uses a
    # different session-name prefix so terminal + swarm worker pools never
    # collide. Same pipe-pane FIFO contract — Rails-side StreamPump reads
    # the FIFO and rebroadcasts to SwarmChannel.
    class SwarmTmuxBridge
      def create(assignment_id:, profile_slug:, cwd:, cols: 120, rows: 40)
        name = name_for(assignment_id)
        run!("tmux", "new-session", "-d", "-s", name, "-x", cols.to_s, "-y", rows.to_s, "-c", cwd)
        fifo = Pathname.new(Rails.root.join("tmp/sockets/swarm-#{Integer(assignment_id)}.fifo"))
        FileUtils.mkdir_p(fifo.dirname)
        unless File.exist?(fifo)
          File.mkfifo(fifo.to_s)
          File.chmod(0o600, fifo.to_s)
        end
        run!("tmux", "pipe-pane", "-t", name, "-o", "cat >> #{Shellwords.escape(fifo.to_s)}")
        { tmux_session_name: name, fifo: fifo.to_s }
      end

      def send_keys(assignment_id:, data:)
        run!("tmux", "send-keys", "-t", name_for(assignment_id), "-l", data.to_s)
        { ok: true }
      end

      def close(assignment_id:)
        out, status = Open3.capture2e("tmux", "kill-session", "-t", name_for(assignment_id))
        # idempotent — kill-session of a missing session is not an error
        if status.success?
          { ok: true }
        elsif out.include?("can't find session")
          { ok: true, already_gone: true }
        else
          raise "tmux kill-session failed: #{out}"
        end
      end

      private
        def name_for(id) = "mop-swarm-#{Integer(id)}"

        def run!(*argv)
          out, status = Open3.capture2e(*argv)
          raise "tmux command failed: #{argv.inspect}\n#{out}" unless status.success?
          out
        end
    end
  end
  ```

  Register handlers — in the `handle_request` lambda, alongside `terminal.*`:

  ```ruby
  swarm = AgentsSupervisor::SwarmTmuxBridge.new
  # ...
  when "swarm.spawn_worker" then swarm.create(**params)
  when "swarm.send_keys"    then swarm.send_keys(**params)
  when "swarm.close_worker" then swarm.close(**params)
  ```

- [ ] **Step 3: Rails-side facade.**

  `app/services/swarm/tmux_bridge.rb`:

  ```ruby
  module Swarm
    class TmuxBridge
      def self.spawn_worker(assignment)
        cwd = WorkspacePath.resolve(root: ".", raw: relative_cwd(assignment.agent_profile.cwd)).to_s
        AgentsSupervisor::Client.call(
          "swarm.spawn_worker",
          {
            assignment_id: assignment.id,
            profile_slug:  assignment.agent_profile.slug,
            cwd:           cwd,
            cols:          120,
            rows:          40
          }
        )
      end

      def self.send_keys(assignment, data)
        AgentsSupervisor::Client.call("swarm.send_keys",
                                     { assignment_id: assignment.id, data: data })
      end

      def self.close_worker(assignment)
        AgentsSupervisor::Client.call("swarm.close_worker", { assignment_id: assignment.id })
      end

      def self.fifo_path(assignment)
        Rails.root.join("tmp/sockets/swarm-#{assignment.id}.fifo")
      end

      private_class_method def self.relative_cwd(raw_cwd)
        # Same shape as Terminal::TmuxManager.relative_cwd — hardens against
        # workspace escapes before reaching tmux.
        base = Pathname.new(Rails.application.config.x.mop_home).realpath
        candidate = Pathname.new(raw_cwd.to_s)
        if candidate.absolute?
          candidate.cleanpath.relative_path_from(base).to_s
        else
          raw_cwd.to_s.presence || "."
        end
      end
    end
  end
  ```

- [ ] **Step 4: Bridge unit test.**

  `test/services/swarm/tmux_bridge_test.rb`:

  ```ruby
  require "test_helper"

  class Swarm::TmuxBridgeTest < ActiveSupport::TestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
      @assignment = SwarmAssignment.create!(
        swarm_mission: swarm_missions(:alpha),
        agent_profile: AgentProfile.find_by!(slug: "backend"),
        task: "T", state: :pending)
    end

    test "spawn_worker calls supervisor with hardened cwd" do
      captured = nil
      with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params) {
        captured = [ method, params ]
        { tmux_session_name: "mop-swarm-#{@assignment.id}", fifo: "/tmp/x" }
      }) do
        Swarm::TmuxBridge.spawn_worker(@assignment)
      end
      assert_equal "swarm.spawn_worker", captured.first
      assert_equal @assignment.id, captured.last[:assignment_id]
      assert_equal "backend",      captured.last[:profile_slug]
    end

    test "close_worker delegates" do
      captured = nil
      with_singleton_method(AgentsSupervisor::Client, :call, ->(method, params) {
        captured = [ method, params ]
        { ok: true }
      }) do
        Swarm::TmuxBridge.close_worker(@assignment)
      end
      assert_equal [ "swarm.close_worker", { assignment_id: @assignment.id } ], captured
    end
  end
  ```

- [ ] **Step 5: Run tests.**

  ```
  bin/rails test test/services/swarm/tmux_bridge_test.rb
  bin/rails test test/integration/supervisor_v3_test.rb
  ```

  Expected: green (or skipped without tmux on CI — that's acceptable, mirrors Phase 4's terminal system test).

- [ ] **Step 6: Commit.**

  ```
  Phase 6 Task 6.10: supervisor v3 — swarm.spawn_worker/send_keys/close_worker + Swarm::TmuxBridge facade
  ```

---

## Task 6.11 — `SwarmChannel` + worker output stream pump

The supervisor pipes worker stdout into a FIFO at `tmp/sockets/swarm-<id>.fifo`. A long-running pump thread inside `Solid Queue` (or a recurring job, see Step 3 below) drains each FIFO and:

1. Broadcasts each chunk to `SwarmChannel.broadcast_to(mission, ...)` for live UI.
2. Buffers the chunk per-assignment for the next orchestrator tick to parse for checkpoints.

For Phase 6 we keep the pump model simple: the orchestrator tick (every 30s) reads the FIFO non-blockingly via `IO.read_nonblock` in a short burst, appending to an in-process buffer keyed by assignment_id. (A dedicated pump thread can land in 6.5 if 30s lag is unacceptable; the system test in 6.23 tolerates it.)

**Files:**
- Create: `app/channels/swarm_channel.rb`
- Create: `app/services/swarm/output_buffer.rb` (thread-safe in-process buffer)
- Create: `test/channels/swarm_channel_test.rb`
- Create: `test/services/swarm/output_buffer_test.rb`

- [ ] **Step 1: Channel test (cross-tenancy + happy-path).**

  ```ruby
  require "test_helper"

  class SwarmChannelTest < ActionCable::Channel::TestCase
    setup { Current.user = users(:one) }

    test "subscribes to the mission stream when the user owns it" do
      mission = swarm_missions(:alpha)
      stub_connection current_user: users(:one)
      subscribe(swarm_mission_id: mission.id)
      assert subscription.confirmed?
      assert_has_stream_for mission
    end

    test "rejects subscription when the user does not own the mission" do
      mission = swarm_missions(:alpha)  # belongs to users(:one) via fixture
      stub_connection current_user: users(:two)  # see Task 6.0 Step 4
      subscribe(swarm_mission_id: mission.id)
      assert subscription.rejected?
    end
  end
  ```

- [ ] **Step 2: Channel + buffer.**

  `app/channels/swarm_channel.rb`:

  ```ruby
  class SwarmChannel < ApplicationCable::Channel
    def subscribed
      mission = current_user.swarm_missions.find_by(id: params[:swarm_mission_id])
      if mission
        stream_for mission
      else
        Rails.logger.info("[SwarmChannel] reject: user=#{current_user.id} swarm_mission_id=#{params[:swarm_mission_id]}")
        reject
      end
    end
  end
  ```

  Add `has_many :swarm_missions, dependent: :destroy` to `app/models/user.rb`.

  `app/services/swarm/output_buffer.rb`:

  ```ruby
  module Swarm
    # In-process per-assignment FIFO-drain buffer. Thread-safe; one instance
    # per Puma+SolidQueue worker. Held by Swarm::OrchestratorLoopJob between
    # ticks to avoid re-opening the FIFO every cycle.
    class OutputBuffer
      MAX_BUFFER_BYTES = 4 * 1024 * 1024

      def self.singleton
        @singleton ||= new
      end

      def initialize
        @mutex   = Mutex.new
        @buffers = Hash.new { |h, k| h[k] = +"" }
        @fifos   = {}
      end

      def drain(assignment)
        @mutex.synchronize do
          fifo = (@fifos[assignment.id] ||= File.open(Swarm::TmuxBridge.fifo_path(assignment), "r+"))
          loop do
            chunk = fifo.read_nonblock(64 * 1024)
            @buffers[assignment.id] << chunk
            SwarmChannel.broadcast_to(assignment.swarm_mission,
                                      { type: "worker_output", assignment_id: assignment.id, chunk: chunk })
            break if chunk.bytesize < 64 * 1024
          end
        rescue IO::WaitReadable, Errno::EAGAIN
          # No more data right now.
        rescue Errno::ENOENT
          # FIFO not yet created (supervisor hasn't dispatched).
        ensure
          enforce_cap(assignment.id)
        end
      end

      def consume(assignment_id)
        @mutex.synchronize do
          out = @buffers[assignment_id].dup
          @buffers[assignment_id].clear
          out
        end
      end

      def close(assignment_id)
        @mutex.synchronize do
          @fifos.delete(assignment_id)&.close rescue nil
          @buffers.delete(assignment_id)
        end
      end

      private
        def enforce_cap(id)
          buf = @buffers[id]
          if buf.bytesize > MAX_BUFFER_BYTES
            overflow = buf.bytesize - MAX_BUFFER_BYTES
            @buffers[id] = buf.byteslice(overflow, MAX_BUFFER_BYTES).to_s
          end
        end
    end
  end
  ```

- [ ] **Step 3: Buffer test.**

  ```ruby
  require "test_helper"

  class Swarm::OutputBufferTest < ActiveSupport::TestCase
    test "consume returns and clears buffered content" do
      buf = Swarm::OutputBuffer.new
      buf.instance_variable_get(:@buffers)[42] << "hello"
      buf.instance_variable_get(:@buffers)[42] << " world"
      assert_equal "hello world", buf.consume(42)
      assert_equal "", buf.consume(42)
    end

    test "enforce_cap evicts oldest bytes" do
      buf = Swarm::OutputBuffer.new
      buf.instance_variable_get(:@buffers)[1] << "x" * (Swarm::OutputBuffer::MAX_BUFFER_BYTES + 100)
      buf.send(:enforce_cap, 1)
      assert_equal Swarm::OutputBuffer::MAX_BUFFER_BYTES, buf.instance_variable_get(:@buffers)[1].bytesize
    end
  end
  ```

- [ ] **Step 4: Run tests.**

  ```
  bin/rails test test/channels/swarm_channel_test.rb test/services/swarm/output_buffer_test.rb
  ```

  Expected: green.

- [ ] **Step 5: Commit.**

  ```
  Phase 6 Task 6.11: SwarmChannel + Swarm::OutputBuffer (FIFO drain + broadcast + buffered for parser)
  ```

---

## Task 6.12 — `SwarmAssignment::Dispatchable` + `SwarmAssignment.dispatch_ready`

Transitions: `pending → dispatched → running → completed | failed | blocked | cancelled`. `dispatch!` is the `pending → dispatched` step; the worker is spawned in tmux and the first kickoff prompt is sent via `send_keys`. `mark_running!` flips on first non-empty output. `block!`, `complete!`, `fail!`, `unblock!` are the explicit transition methods (no enum flips outside these).

**Files:**
- Create: `app/models/swarm_assignment/dispatchable.rb`
- Modify: `app/models/swarm_assignment.rb` (include `Dispatchable`)
- Create: `test/models/swarm_assignment/dispatchable_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmAssignment::DispatchableTest < ActiveSupport::TestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
    end

    test "dispatch! calls TmuxBridge.spawn_worker + transitions to :dispatched + tracks event" do
      asg = SwarmAssignment.create!(swarm_mission: swarm_missions(:alpha),
                                    agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "Build the X feature")
      spawn_args = nil
      send_keys_args = nil
      with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(a) {
        spawn_args = a
        { tmux_session_name: "mop-swarm-#{a.id}", fifo: "/tmp/x" }
      }) do
        with_singleton_method(Swarm::TmuxBridge, :send_keys, ->(a, data) {
          send_keys_args = [ a, data ]
        }) do
          assert_difference -> { Event.where(action: "swarm_assignment_dispatched").count }, 1 do
            asg.dispatch!
          end
        end
      end
      assert_equal asg,                       spawn_args
      assert_equal asg,                       send_keys_args.first
      assert_match(/Build the X feature/,     send_keys_args.last)
      assert_predicate asg, :dispatched?
      assert_equal "mop-swarm-#{asg.id}", asg.tmux_session_name
      assert_not_nil asg.dispatched_at
    end

    test "dispatch_ready dispatches all unblocked pending assignments" do
      mission = swarm_missions(:alpha)
      first = SwarmAssignment.create!(swarm_mission: mission, agent_profile: AgentProfile.find_by!(slug: "backend"),
                                      task: "T1", state: :completed)
      ready = SwarmAssignment.create!(swarm_mission: mission, agent_profile: AgentProfile.find_by!(slug: "frontend"),
                                      task: "T2", depends_on: [ first.id ])
      not_ready = SwarmAssignment.create!(swarm_mission: mission, agent_profile: AgentProfile.find_by!(slug: "frontend"),
                                          task: "T3", depends_on: [ ready.id ])
      with_singleton_method(Swarm::TmuxBridge, :spawn_worker, ->(_) { { tmux_session_name: "x", fifo: "/tmp/x" } }) do
        with_singleton_method(Swarm::TmuxBridge, :send_keys, ->(_a, _d) { nil }) do
          SwarmAssignment.dispatch_ready(mission: mission)
        end
      end
      assert_predicate ready.reload, :dispatched?
      assert_predicate not_ready.reload, :pending?
    end

    test "block!(reason) flips to :blocked, records reason, fires event, flips mission to :blocked" do
      asg = SwarmAssignment.create!(swarm_mission: swarm_missions(:alpha),
                                    agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "T", state: :running)
      assert_difference -> { Event.where(action: "swarm_assignment_blocked").count }, 1 do
        asg.block!(reason: "Need DB creds")
      end
      assert_predicate asg, :blocked?
      assert_equal "Need DB creds", asg.block_reason
      assert_predicate asg.swarm_mission.reload, :blocked?
    end

    test "complete! tears down the tmux session and runs orchestrator advance" do
      asg = SwarmAssignment.create!(swarm_mission: swarm_missions(:alpha),
                                    agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "T", state: :running, tmux_session_name: "mop-swarm-1")
      closed = nil
      with_singleton_method(Swarm::TmuxBridge, :close_worker, ->(a) { closed = a; { ok: true } }) do
        asg.complete!
      end
      assert_equal asg, closed
      assert_predicate asg, :completed?
      assert_not_nil asg.finished_at
    end
  end
  ```

- [ ] **Step 2: `Dispatchable` concern.**

  ```ruby
  module SwarmAssignment::Dispatchable
    extend ActiveSupport::Concern

    KICKOFF_TEMPLATE = <<~PROMPT
      You are a swarm worker. Your task:

      %{task}

      When you reach a milestone (or are blocked), emit a YAML checkpoint
      between these sentinels (no other text inside):

      ===HERMES CHECKPOINT===
      state_label: <one-token>
      runtime_state: { step: 1 }
      files_changed: []
      commands_run: []
      result: <short prose>
      blocker: null              # set to a string if you cannot proceed
      next_action: <short prose>
      ===END CHECKPOINT===

      Begin.
    PROMPT

    class_methods do
      def dispatch_ready(mission:)
        mission.assignments.ready.each(&:dispatch!)
      end
    end

    def dispatch!
      return unless pending?

      transaction do
        result = Swarm::TmuxBridge.spawn_worker(self)
        update!(state: :dispatched,
                tmux_session_name: result[:tmux_session_name] || result["tmux_session_name"],
                dispatched_at: Time.current)
        track_event :dispatched, agent_slug: agent_profile.slug
      end
      Swarm::TmuxBridge.send_keys(self, kickoff_prompt + "\n")
      SwarmEvent.log!(mission: swarm_mission, assignment: self,
                      kind: "dispatched", message: "Worker spawned",
                      data: { tmux: tmux_session_name })
    end

    def mark_running!
      return unless dispatched?
      update!(state: :running)
      track_event :started
    end

    def complete!
      return if resolved?
      Swarm::TmuxBridge.close_worker(self) rescue nil
      update!(state: :completed, finished_at: Time.current)
      track_event :completed
    end

    def fail!(reason: nil)
      return if resolved?
      Swarm::TmuxBridge.close_worker(self) rescue nil
      update!(state: :failed, finished_at: Time.current, block_reason: reason)
      track_event :failed, reason: reason
    end

    def cancel!
      return if resolved?
      Swarm::TmuxBridge.close_worker(self) rescue nil
      update!(state: :cancelled, finished_at: Time.current)
      track_event :cancelled
    end

    def block!(reason:)
      return unless %w[dispatched running].include?(state)
      transaction do
        update!(state: :blocked, block_reason: reason)
        swarm_mission.update!(state: :blocked) unless swarm_mission.blocked?
        track_event :blocked, reason: reason
      end
      SwarmEvent.log!(mission: swarm_mission, assignment: self,
                      kind: "blocked", message: reason, data: {})
    end

    def unblock!(operator_input:)
      return unless blocked?
      Swarm::TmuxBridge.send_keys(self, operator_input + "\n")
      update!(state: :running, block_reason: nil)
      track_event :unblocked
    end

    private
      def kickoff_prompt
        format(KICKOFF_TEMPLATE, task: task)
      end
  end
  ```

  Add `include Dispatchable` to `app/models/swarm_assignment.rb`.

- [ ] **Step 3: Run tests.**

  ```
  bin/rails test test/models/swarm_assignment/dispatchable_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.12: SwarmAssignment::Dispatchable — dispatch!/mark_running!/complete!/fail!/cancel!/block!/unblock! + dispatch_ready
  ```

---

## Task 6.13 — `SwarmMission::Advanceable` + `Swarm::OrchestratorLoopJob`

The recurring orchestrator drains every active mission's output buffer, parses checkpoints, applies state transitions:

- Any `state_label` value other than the previous → record `SwarmCheckpoint` row.
- `blocker: "..."` → `assignment.block!(reason: blocker)`.
- `state_label: "done"` (or `result` filled + `next_action` nil) → `assignment.complete!`.
- All assignments resolved (`completed | failed | cancelled`) → `mission.complete!`.
- Any failure: `assignment.fail!`.

**Files:**
- Create: `app/models/swarm_mission/advanceable.rb`
- Create: `app/jobs/swarm/orchestrator_loop_job.rb`
- Modify: `app/models/swarm_mission.rb` (include `Advanceable`)
- Modify: `config/recurring.yml` (add `swarm_orchestrator` recurring entry, every 30s)
- Create: `test/models/swarm_mission/advanceable_test.rb`
- Create: `test/jobs/swarm/orchestrator_loop_job_test.rb`

- [ ] **Step 1: Failing test for `advance!`.**

  ```ruby
  require "test_helper"

  class SwarmMission::AdvanceableTest < ActiveSupport::TestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
    end

    def push_output(asg, text)
      Swarm::OutputBuffer.singleton.instance_variable_get(:@buffers)[asg.id] << text
    end

    test "advance! parses a checkpoint and creates a SwarmCheckpoint row" do
      mission = swarm_missions(:alpha); mission.update!(state: :executing)
      asg = SwarmAssignment.create!(swarm_mission: mission,
                                    agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "T", state: :running)
      push_output(asg, <<~OUT)
        ===HERMES CHECKPOINT===
        state_label: working
        runtime_state: { step: 1 }
        files_changed: ["a.rb"]
        commands_run: []
        result: "Made progress"
        blocker: null
        next_action: "Keep going"
        ===END CHECKPOINT===
      OUT

      assert_difference -> { asg.checkpoints.count }, 1 do
        mission.advance!
      end
      cp = asg.checkpoints.last
      assert_equal "working", cp.state_label
      assert_predicate asg.reload, :running?
    end

    test "advance! detects blocker → assignment.block! + mission flips to :blocked" do
      mission = swarm_missions(:alpha); mission.update!(state: :executing)
      asg = SwarmAssignment.create!(swarm_mission: mission,
                                    agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "T", state: :running)
      push_output(asg, <<~OUT)
        ===HERMES CHECKPOINT===
        state_label: stuck
        runtime_state: {}
        files_changed: []
        commands_run: []
        result: null
        blocker: "Need credentials"
        next_action: null
        ===END CHECKPOINT===
      OUT
      mission.advance!
      assert_predicate asg.reload, :blocked?
      assert_predicate mission.reload, :blocked?
    end

    test "advance! completes assignment + completes mission once all assignments resolve" do
      mission = swarm_missions(:alpha); mission.update!(state: :executing)
      asg = SwarmAssignment.create!(swarm_mission: mission,
                                    agent_profile: AgentProfile.find_by!(slug: "backend"),
                                    task: "T", state: :running)
      push_output(asg, <<~OUT)
        ===HERMES CHECKPOINT===
        state_label: done
        runtime_state: {}
        files_changed: []
        commands_run: []
        result: "All wrapped up"
        blocker: null
        next_action: null
        ===END CHECKPOINT===
      OUT
      mission.advance!
      assert_predicate asg.reload, :completed?
      assert_predicate mission.reload, :complete?
    end

    test ".advance_all_active processes every non-terminal mission" do
      m1 = swarm_missions(:alpha);     m1.update!(state: :executing)
      swarm_missions(:alpha_cancelled)  # already cancelled, will be filtered by .active
      called_on = []
      with_singleton_method(SwarmMission, :active, -> { [ m1 ] }) do
        with_singleton_method(m1, :advance!, -> { called_on << m1 }) do
          SwarmMission.advance_all_active
        end
      end
      assert_equal [ m1 ], called_on
    end
  end
  ```

- [ ] **Step 2: `Advanceable` concern.**

  ```ruby
  module SwarmMission::Advanceable
    extend ActiveSupport::Concern

    class_methods do
      def advance_all_active
        SwarmMission.active.find_each(&:advance!)
      end
    end

    def advance!
      return if planning? || resolved_terminally?

      assignments.live.find_each do |asg|
        process_assignment(asg)
      end

      transition_after_assignments
    end

    private
      def resolved_terminally?
        complete? || cancelled?
      end

      def process_assignment(asg)
        Swarm::OutputBuffer.singleton.drain(asg)
        text = Swarm::OutputBuffer.singleton.consume(asg.id)
        return if text.empty?

        asg.mark_running! if asg.dispatched?
        SwarmCheckpoint.parse(text).each { |stanza| apply_stanza(asg, stanza) }
      end

      def apply_stanza(asg, stanza)
        asg.checkpoints.create!(
          state_label:   stanza[:state_label],
          runtime_state: stanza[:runtime_state],
          files_changed: stanza[:files_changed],
          commands_run:  stanza[:commands_run],
          result:        stanza[:result],
          blocker:       stanza[:blocker],
          next_action:   stanza[:next_action],
          raw:           stanza[:raw]
        )
        SwarmEvent.log!(mission: self, assignment: asg, kind: "checkpoint",
                        message: stanza[:state_label], data: stanza.except(:raw))

        if stanza[:blocker].present?
          asg.block!(reason: stanza[:blocker])
        elsif stanza[:state_label] == "done" || (stanza[:result].present? && stanza[:next_action].blank?)
          asg.complete!
        end
      end

      def transition_after_assignments
        if assignments.where(state: %i[pending dispatched running blocked]).empty?
          if assignments.where(state: :failed).any?
            update!(state: :complete)  # All-resolved-with-some-failures still terminal; UI surfaces failures
            track_event :completed_with_failures, count: assignments.where(state: :failed).count
          else
            update!(state: :complete)
            track_event :completed
          end
          SwarmEvent.log!(mission: self, kind: "completed", message: "All assignments resolved", data: {})
        elsif dispatching? && assignments.where(state: :dispatched).none?
          update!(state: :executing) if assignments.where(state: :running).any?
        elsif !blocked? && assignments.where(state: :blocked).empty? && executing?
          # Trigger ready dispatch if mode is :auto
          SwarmAssignment.dispatch_ready(mission: self) if auto?
        end
      end
  end
  ```

  Add `include Advanceable` to `SwarmMission`.

- [ ] **Step 3: Recurring job + recurring.yml.**

  `app/jobs/swarm/orchestrator_loop_job.rb`:

  ```ruby
  module Swarm
    class OrchestratorLoopJob < ApplicationJob
      limits_concurrency to: 1, key: "swarm_orchestrator", on_conflict: :discard

      def perform = SwarmMission.advance_all_active
    end
  end
  ```

  In `config/recurring.yml`, add under `production:`:

  ```yaml
    swarm_orchestrator:
      class: Swarm::OrchestratorLoopJob
      schedule: every 30 seconds
  ```

- [ ] **Step 4: Job test.**

  ```ruby
  require "test_helper"

  class Swarm::OrchestratorLoopJobTest < ActiveSupport::TestCase
    test "perform calls SwarmMission.advance_all_active" do
      called = false
      with_singleton_method(SwarmMission, :advance_all_active, -> { called = true }) do
        Swarm::OrchestratorLoopJob.new.perform
      end
      assert called
    end
  end
  ```

- [ ] **Step 5: Run tests.**

  ```
  bin/rails test test/models/swarm_mission/advanceable_test.rb test/jobs/swarm/orchestrator_loop_job_test.rb
  ```

  Expected: green.

- [ ] **Step 6: Commit.**

  ```
  Phase 6 Task 6.13: SwarmMission::Advanceable + OrchestratorLoopJob (recurring 30s, limits_concurrency to:1)
  ```

---

## Task 6.14 — `SwarmMission#dispatch!` + mode-aware auto-flow

`decompose!` (6.9) leaves the mission in `:dispatching`. `dispatch!` is the explicit transition that starts the first wave of `dispatch_ready` workers and flips the mission to `:executing`. In `:manual` mode, the operator hits a "Start" button; in `:auto`, the controller calls `dispatch!` immediately after `decompose!`.

**Files:**
- Modify: `app/models/swarm_mission.rb` (add `dispatch!` method directly on the model — not a concern; it's two lines)
- Create: `test/models/swarm_mission/dispatch_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmMissionDispatchTest < ActiveSupport::TestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
    end

    test "dispatch! transitions :dispatching → :executing and calls dispatch_ready" do
      mission = swarm_missions(:alpha); mission.update!(state: :dispatching)
      SwarmAssignment.create!(swarm_mission: mission,
                              agent_profile: AgentProfile.find_by!(slug: "backend"),
                              task: "T")
      called_with = nil
      with_singleton_method(SwarmAssignment, :dispatch_ready, ->(mission:) { called_with = mission }) do
        mission.dispatch!
      end
      assert_equal mission, called_with
      assert_predicate mission, :executing?
    end

    test "dispatch! is a no-op outside :dispatching" do
      mission = swarm_missions(:alpha); mission.update!(state: :executing)
      called = false
      with_singleton_method(SwarmAssignment, :dispatch_ready, ->(**) { called = true }) do
        mission.dispatch!
      end
      refute called
    end
  end
  ```

- [ ] **Step 2: Implement.**

  Add to `app/models/swarm_mission.rb`:

  ```ruby
  def dispatch!
    return unless dispatching?

    transaction do
      update!(state: :executing)
      SwarmAssignment.dispatch_ready(mission: self)
      track_event :dispatched
    end
    SwarmEvent.log!(mission: self, kind: "executing", message: "Mission started", data: {})
  end
  ```

- [ ] **Step 3: Run test.**

  ```
  bin/rails test test/models/swarm_mission/dispatch_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.14: SwarmMission#dispatch! (mode-aware orchestrator entry point)
  ```

---

## Task 6.15 — Routes + `SwarmMissionsController` + `SwarmMissionScoped`

CRUD on missions; create flow takes title + goal + mode, kicks off `decompose_later`.

**Files:**
- Modify: `config/routes.rb` (add `resources :swarm_missions` block per workflows § 9 + `agent_profiles` + `swarm_kanbans#show`)
- Create: `app/controllers/concerns/swarm_mission_scoped.rb`
- Create: `app/controllers/swarm_missions_controller.rb`
- Create: `app/controllers/swarm_missions/assignments_controller.rb`
- Create: `app/controllers/swarm_missions/cancellations_controller.rb`
- Create: `app/views/swarm_missions/{index,show,new,_form,_mission_row}.html.erb`
- Create: `test/controllers/swarm_missions_controller_test.rb`
- Create: `test/controllers/swarm_missions/cancellations_controller_test.rb`

- [ ] **Step 1: Routes.**

  Append to `config/routes.rb` (between `resources :scheduled_jobs` and `resources :mcp_servers`):

  ```ruby
  resources :swarm_missions, path: "swarm/missions" do
    scope module: :swarm_missions do
      resources :assignments,  only: %i[update]
      resource  :cancellation, only: %i[create]
    end
  end
  get "/swarm/kanban", to: "swarm_kanbans#show", as: :swarm_kanban
  resources :agent_profiles, path: "swarm/agents"
  ```

- [ ] **Step 2: Failing controller test.**

  ```ruby
  require "test_helper"

  class SwarmMissionsControllerTest < ActionDispatch::IntegrationTest
    include CrossTenancyAssertions

    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
      sign_in_as users(:one)
    end

    test "create kicks off decompose_later + redirects to show" do
      assert_enqueued_with(job: Swarm::DecompositionJob) do
        post swarm_missions_path,
             params: { swarm_mission: { title: "M", goal: "Build the X", mode: "auto" } }
      end
      mission = SwarmMission.order(:id).last
      assert_redirected_to swarm_mission_path(mission)
    end

    test "show returns 404 for missions owned by another user" do
      # users(:two) added in Task 6.0 Step 4 specifically for cross-tenancy tests.
      mission = SwarmMission.create!(user: users(:two), created_by: users(:two), title: "X", goal: "Y")
      assert_404_for_cross_tenant_show swarm_mission_path(mission)
    end
  end
  ```

  (Use the Phase 1 `CrossTenancyAssertions` helper.)

- [ ] **Step 3: Concern + controller.**

  ```ruby
  module SwarmMissionScoped
    extend ActiveSupport::Concern
    included { before_action :set_swarm_mission }

    private
      def set_swarm_mission
        @swarm_mission = Current.user.swarm_missions.find(params[:swarm_mission_id] || params[:id])
      end
  end
  ```

  `app/controllers/swarm_missions_controller.rb`:

  ```ruby
  class SwarmMissionsController < ApplicationController
    include SwarmMissionScoped
    skip_before_action :set_swarm_mission, only: %i[index new create]

    def index
      @missions = Current.user.swarm_missions.recent
    end

    def show
      @assignments = @swarm_mission.assignments.includes(:agent_profile, :checkpoints)
      @feed        = @swarm_mission.swarm_events.recent.limit(100)
    end

    def new
      @swarm_mission = SwarmMission.new(mode: :auto)
    end

    def create
      @swarm_mission = SwarmMission.new(swarm_mission_params.merge(user: Current.user, created_by: Current.user))
      if @swarm_mission.save
        @swarm_mission.track_event :created
        @swarm_mission.decompose_later
        redirect_to swarm_mission_path(@swarm_mission)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @swarm_mission.update(swarm_mission_params)
        redirect_to swarm_mission_path(@swarm_mission)
      else
        render :show, status: :unprocessable_entity
      end
    end

    def destroy
      @swarm_mission.destroy
      redirect_to swarm_missions_path
    end

    private
      def swarm_mission_params
        params.require(:swarm_mission).permit(:title, :goal, :mode)
      end
  end
  ```

  `app/controllers/swarm_missions/cancellations_controller.rb`:

  ```ruby
  class SwarmMissions::CancellationsController < ApplicationController
    include SwarmMissionScoped

    def create
      @swarm_mission.cancel(reason: params[:reason], user: Current.user)
      redirect_to swarm_mission_path(@swarm_mission)
    end
  end
  ```

  `app/controllers/swarm_missions/assignments_controller.rb` (update endpoint = unblock with operator input OR mark review_required):

  ```ruby
  class SwarmMissions::AssignmentsController < ApplicationController
    include SwarmMissionScoped

    def update
      asg = @swarm_mission.assignments.find(params[:id])
      if params[:operator_input].present?
        asg.unblock!(operator_input: params[:operator_input])
      elsif params.key?(:review_required)
        asg.update!(review_required: params[:review_required] == "true")
      end
      redirect_to swarm_mission_path(@swarm_mission)
    end
  end
  ```

- [ ] **Step 4: Views (minimum viable; rendered with default layout + the chat-session card CSS).**

  See `app/views/scheduled_jobs/*.html.erb` for template patterns. Inline only the essentials:

  `app/views/swarm_missions/index.html.erb`:

  ```erb
  <h1>Missions</h1>
  <%= link_to "New mission", new_swarm_mission_path, class: "button" %>
  <ul class="missions">
    <% @missions.each do |m| -%>
      <%= render "mission_row", mission: m %>
    <% end -%>
  </ul>
  ```

  `app/views/swarm_missions/_mission_row.html.erb`:

  ```erb
  <li class="mission mission--<%= mission.state %>">
    <%= link_to mission.title, swarm_mission_path(mission) %>
    <span class="badge"><%= mission.state.humanize %></span>
    <span class="meta"><%= mission.assignments.size %> assignments · <%= time_ago_in_words(mission.created_at) %> ago</span>
  </li>
  ```

  `app/views/swarm_missions/new.html.erb`, `show.html.erb`, and `_form.html.erb` — see `app/views/scheduled_jobs/{new,show,_form}.html.erb` for the layout; adapt fields to `:title`, `:goal`, `:mode` (radio: auto/manual).

  Show page must:
  - Stream-subscribe via `<%= turbo_stream_from @swarm_mission %>` (Turbo channel) AND `<%= action_cable_meta_tag %>` already in layout.
  - Render assignments table with state badge + `block_reason` + an inline form for `unblock!` when `blocked?`.
  - Render `@feed` (SwarmEvent list).

- [ ] **Step 5: Run tests.**

  ```
  bin/rails test test/controllers/swarm_missions_controller_test.rb
  ```

  Expected: green.

- [ ] **Step 6: Commit.**

  ```
  Phase 6 Task 6.15: SwarmMissions routes/controller/views + scoped concern + cancellation/assignment sub-controllers
  ```

---

## Task 6.16 — `SwarmKanbansController` + kanban view + `kanban_controller.js`

A single page showing every active assignment across the user's missions, grouped into columns by state. Drag-and-drop moves between `blocked → running` (manual unblock) and `pending → dispatched` (manual dispatch).

**Files:**
- Create: `app/controllers/swarm_kanbans_controller.rb`
- Create: `app/views/swarm_kanbans/show.html.erb`
- Create: `app/javascript/controllers/kanban_controller.js`
- Modify: `app/javascript/controllers/index.js` (register)
- Modify: `config/importmap.rb` (pin `sortablejs` for drag-drop)
- Create: `test/controllers/swarm_kanbans_controller_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmKanbansControllerTest < ActionDispatch::IntegrationTest
    setup { sign_in_as users(:one) }

    test "show only includes the current user's assignments" do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
      mine_mission = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "M1", goal: "g", state: :executing)
      mine = SwarmAssignment.create!(swarm_mission: mine_mission,
                                     agent_profile: AgentProfile.find_by!(slug: "backend"),
                                     task: "Mine", state: :running)
      Current.user = users(:two)
      theirs_mission = SwarmMission.create!(user: users(:two), created_by: users(:two), title: "M2", goal: "g", state: :executing)
      theirs = SwarmAssignment.create!(swarm_mission: theirs_mission,
                                       agent_profile: AgentProfile.find_by!(slug: "backend"),
                                       task: "Theirs", state: :running)
      Current.user = users(:one)

      get swarm_kanban_path
      assert_response :ok
      assert_match "Mine", response.body
      assert_no_match(/Theirs/, response.body)
    end
  end
  ```

- [ ] **Step 2: Controller.**

  ```ruby
  class SwarmKanbansController < ApplicationController
    def show
      @columns = SwarmAssignment::COLUMNS.index_with do |state|
        Current.user.swarm_missions.joins(:assignments)
                    .merge(SwarmAssignment.where(state: state))
                    .includes(assignments: :agent_profile)
      end
      # ...alternative: load assignments directly, group by state — see view
      @assignments_by_state = Current.user.swarm_missions.flat_map { |m| m.assignments.includes(:agent_profile) }
                                          .group_by(&:state)
    end
  end
  ```

  Add `COLUMNS = %w[pending dispatched running blocked completed]` constant to `SwarmAssignment`.

  `app/views/swarm_kanbans/show.html.erb`:

  ```erb
  <h1>Kanban</h1>
  <div class="kanban" data-controller="kanban">
    <% SwarmAssignment::COLUMNS.each do |col| -%>
      <div class="kanban__column" data-kanban-state-param="<%= col %>">
        <h2><%= col.humanize %></h2>
        <ul data-kanban-target="column">
          <% Array(@assignments_by_state[col]).each do |a| -%>
            <li class="kanban__card" data-assignment-id="<%= a.id %>">
              <%= link_to a.task.truncate(60), swarm_mission_path(a.swarm_mission) %>
              <small><%= a.agent_profile.display_name %></small>
            </li>
          <% end -%>
        </ul>
      </div>
    <% end -%>
  </div>
  ```

- [ ] **Step 3: Stimulus controller.**

  Pin in `config/importmap.rb`: `pin "sortablejs", to: "https://esm.sh/sortablejs@1.15.0"`.

  `app/javascript/controllers/kanban_controller.js`:

  ```js
  import { Controller } from "@hotwired/stimulus"
  import Sortable from "sortablejs"

  export default class extends Controller {
    static targets = ["column"]

    connect() {
      this.columnTargets.forEach((col) => {
        Sortable.create(col, {
          group: "kanban",
          animation: 150,
          onEnd: (evt) => this.move(evt)
        })
      })
    }

    move(evt) {
      const id    = evt.item.dataset.assignmentId
      const state = evt.to.closest("[data-kanban-state-param]").dataset.kanbanStateParam
      const token = document.querySelector('meta[name="csrf-token"]').content
      // For now, only the unblock manual transition is supported; future
      // transitions (manual pending → dispatched, etc.) land in 6.5.
      fetch(`/swarm/assignments/${id}/move`, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Content-Type": "application/json", "Accept": "text/vnd.turbo-stream.html" },
        body: JSON.stringify({ state })
      })
    }
  }
  ```

  Add a `move` route + controller action — small (5 lines), in `app/controllers/swarm_missions/assignments_controller.rb`:

  ```ruby
  # NOTE: the route is the existing update action; the JS POSTs there. For
  # Phase 6 we accept :state in the params and apply the corresponding
  # transition method, NOT a direct enum write.
  def update
    asg = @swarm_mission.assignments.find(params[:id])
    case params[:state]
    when "dispatched" then asg.dispatch!  if asg.pending?
    when "cancelled"  then asg.cancel!
    end
    if params[:operator_input].present?
      asg.unblock!(operator_input: params[:operator_input])
    end
    redirect_to swarm_mission_path(@swarm_mission), status: :see_other
  end
  ```

- [ ] **Step 4: Run tests.**

  ```
  bin/rails test test/controllers/swarm_kanbans_controller_test.rb
  ```

  Expected: green.

- [ ] **Step 5: Commit.**

  ```
  Phase 6 Task 6.16: SwarmKanbansController + kanban view + Stimulus + sortablejs pin (drag/drop transitions go through model methods)
  ```

---

## Task 6.17 — `AgentProfilesController` (roster + CRUD)

Standard CRUD + a "Sync from YAML" button that hits `AgentProfile.refresh_from_yaml!`.

**Files:**
- Create: `app/controllers/agent_profiles_controller.rb`
- Create: `app/views/agent_profiles/{index,show,new,edit,_form}.html.erb`
- Create: `test/controllers/agent_profiles_controller_test.rb`

- [ ] **Step 1: Failing test (admin gate + sync).**

  ```ruby
  require "test_helper"

  class AgentProfilesControllerTest < ActionDispatch::IntegrationTest
    setup do
      # users(:one) has role: 1 (admin); use it as the admin baseline.
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
      sign_in_as users(:one)
    end

    test "index lists rostered profiles" do
      get agent_profiles_path
      assert_response :ok
      assert_match "Backend Worker", response.body
    end

    test "non-admin gets 403" do
      Current.user = users(:two)
      sign_in_as users(:two)
      get agent_profiles_path
      assert_response :forbidden
    end

    test "sync action upserts from YAML" do
      AgentProfile.delete_all
      post sync_agent_profiles_path
      assert_response :redirect
      assert_operator AgentProfile.count, :>, 0
    end
  end
  ```

- [ ] **Step 2: Controller + admin gate.**

  Add a singular nested route in `config/routes.rb`:

  ```ruby
  resources :agent_profiles, path: "swarm/agents" do
    collection { resource :sync, only: %i[create], controller: "agent_profile_syncs" }
  end
  ```

  `app/controllers/agent_profiles_controller.rb`:

  ```ruby
  class AgentProfilesController < ApplicationController
    before_action :require_admin

    def index
      @profiles = AgentProfile.order(:display_name)
    end

    def show
      @profile = AgentProfile.find(params[:id])
    end

    def new = (@profile = AgentProfile.new)

    def edit = (@profile = AgentProfile.find(params[:id]))

    def create
      @profile = AgentProfile.new(profile_params)
      if @profile.save
        @profile.track_event :created
        redirect_to agent_profile_path(@profile)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @profile = AgentProfile.find(params[:id])
      if @profile.update(profile_params)
        redirect_to agent_profile_path(@profile)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      AgentProfile.find(params[:id]).destroy
      redirect_to agent_profiles_path
    end

    private
      def profile_params
        params.require(:agent_profile).permit(:slug, :display_name, :role, :model, :provider,
                                              :cwd, :enabled, specialties: [], avoid_tasks: [],
                                              skill_ids: [])
      end

      def require_admin
        head :forbidden unless Current.user&.admin?
      end
  end
  ```

  `app/controllers/agent_profile_syncs_controller.rb`:

  ```ruby
  class AgentProfileSyncsController < ApplicationController
    def create
      head :forbidden unless Current.user&.admin?
      AgentProfile.refresh_from_yaml!
      redirect_to agent_profiles_path
    end
  end
  ```

  Views — minimal forms; see `app/views/scheduled_jobs/_form.html.erb` shape.

- [ ] **Step 3: Run tests.**

  ```
  bin/rails test test/controllers/agent_profiles_controller_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.17: AgentProfilesController (admin) + sync from YAML + views
  ```

---

## Task 6.18 — Mission show: live worker chat + checkpoints + event log

Wire the show page so:
- The mission card is `<%= turbo_stream_from @swarm_mission %>` for Turbo Stream broadcasts (already in 6.15).
- Subscribe to `SwarmChannel` via a Stimulus controller that writes chunks into a `<pre>` per-assignment block.

**Files:**
- Modify: `app/views/swarm_missions/show.html.erb`
- Create: `app/views/swarm_missions/_assignment.html.erb`
- Create: `app/views/swarm_missions/_event_feed.html.erb`
- Create: `app/javascript/controllers/swarm_channel_controller.js`
- Modify: `app/javascript/controllers/index.js` (register)

- [ ] **Step 1: Partials.**

  `app/views/swarm_missions/_assignment.html.erb`:

  ```erb
  <article class="assignment assignment--<%= assignment.state %>"
           id="<%= dom_id(assignment) %>"
           data-assignment-id="<%= assignment.id %>">
    <header>
      <strong><%= assignment.agent_profile.display_name %></strong>
      <span class="badge"><%= assignment.state.humanize %></span>
    </header>
    <p class="assignment__task"><%= assignment.task %></p>

    <% if assignment.blocked? -%>
      <%= form_with url: swarm_mission_assignment_path(assignment.swarm_mission, assignment),
                    method: :patch do |f| %>
        <p class="assignment__blocker">Blocker: <%= assignment.block_reason %></p>
        <%= f.text_area :operator_input, placeholder: "Provide the info the worker needs…" %>
        <%= f.submit "Unblock" %>
      <% end %>
    <% end -%>

    <details>
      <summary>Checkpoints (<%= assignment.checkpoints.size %>)</summary>
      <ol>
        <% assignment.checkpoints.order(:created_at).each do |cp| -%>
          <li><strong><%= cp.state_label %></strong> — <%= cp.result %></li>
        <% end -%>
      </ol>
    </details>

    <details>
      <summary>Live output</summary>
      <pre class="worker-output" data-assignment-id="<%= assignment.id %>"></pre>
    </details>
  </article>
  ```

  `app/views/swarm_missions/_event_feed.html.erb`:

  ```erb
  <h2>Event log</h2>
  <ol class="swarm-events">
    <% events.each do |e| -%>
      <li><time><%= e.occurred_at.strftime("%H:%M:%S") %></time>
          <strong><%= e.kind %></strong>
          <%= e.message %></li>
    <% end -%>
  </ol>
  ```

  Edit `app/views/swarm_missions/show.html.erb` to render these:

  ```erb
  <article id="<%= dom_id(@swarm_mission) %>"
           data-controller="swarm-channel"
           data-swarm-channel-mission-id-value="<%= @swarm_mission.id %>">
    <h1><%= @swarm_mission.title %></h1>
    <p><%= @swarm_mission.goal %></p>
    <p class="badge"><%= @swarm_mission.state.humanize %></p>

    <% if @swarm_mission.dispatching? -%>
      <%= button_to "Start mission", swarm_mission_path(@swarm_mission, swarm_mission: { state: "executing" }), method: :patch %>
    <% end -%>

    <% unless @swarm_mission.cancelled? -%>
      <%= button_to "Cancel mission",
                    swarm_mission_cancellation_path(@swarm_mission), method: :post,
                    data: { turbo_confirm: "Cancel and kill all workers?" } %>
    <% end -%>

    <section class="assignments">
      <% @assignments.each do |a| -%>
        <%= render "assignment", assignment: a %>
      <% end -%>
    </section>

    <%= render "event_feed", events: @feed %>
  </article>
  ```

- [ ] **Step 2: Stimulus controller.**

  `app/javascript/controllers/swarm_channel_controller.js`:

  ```js
  import { Controller } from "@hotwired/stimulus"
  import consumer from "channels/consumer"

  export default class extends Controller {
    static values = { missionId: Number }

    connect() {
      this.subscription = consumer.subscriptions.create(
        { channel: "SwarmChannel", swarm_mission_id: this.missionIdValue },
        { received: (data) => this.onMessage(data) }
      )
    }

    disconnect() {
      this.subscription?.unsubscribe()
    }

    onMessage(data) {
      if (data.type === "worker_output") {
        const pre = this.element.querySelector(`pre.worker-output[data-assignment-id="${data.assignment_id}"]`)
        if (pre) pre.appendChild(document.createTextNode(data.chunk))
      }
    }
  }
  ```

- [ ] **Step 3: Run a full system-level smoke (optional in this task; landed in 6.23).** No new test file here — the channel wiring is exercised by `test/channels/swarm_channel_test.rb` (Task 6.11) and the end-to-end system test (Task 6.23). Manually open `/swarm/missions/:id` in `bin/dev` to verify it renders without JS errors.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.18: Mission show — assignments partial + event feed + SwarmChannel Stimulus subscriber
  ```

---

## Task 6.19 — Mode toggle controller action

`SwarmMission#mode` is a column already (Task 6.3). The UI needs a toggle on the show page; the controller's `update` action already accepts `:mode` (Task 6.15). Add tests + JS toggle.

**Files:**
- Modify: `app/views/swarm_missions/show.html.erb` (render mode badge + toggle form)
- Create: `test/controllers/swarm_missions_mode_toggle_test.rb`

- [ ] **Step 1: Failing controller test.**

  ```ruby
  require "test_helper"

  class SwarmMissionsModeToggleTest < ActionDispatch::IntegrationTest
    setup do
      Current.user = users(:one)
      sign_in_as users(:one)
      AgentProfile.refresh_from_yaml!
    end

    test "patch mode flips :auto ↔ :manual" do
      m = SwarmMission.create!(user: users(:one), created_by: users(:one), title: "X", goal: "Y", mode: :auto)
      patch swarm_mission_path(m), params: { swarm_mission: { mode: "manual" } }
      assert_equal "manual", m.reload.mode
    end
  end
  ```

- [ ] **Step 2: View — render toggle.**

  In `show.html.erb`:

  ```erb
  <%= form_with model: @swarm_mission, method: :patch, class: "mode-toggle" do |f| %>
    Mode:
    <%= f.radio_button :mode, "auto"    %> <%= f.label :mode_auto,   "Auto" %>
    <%= f.radio_button :mode, "manual"  %> <%= f.label :mode_manual, "Manual" %>
    <%= f.submit "Save" %>
  <% end %>
  ```

- [ ] **Step 3: Run test.**

  ```
  bin/rails test test/controllers/swarm_missions_mode_toggle_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.19: Mode toggle (auto ↔ manual) on mission show
  ```

---

## Task 6.20 — Manual-mode dispatch button + auto-mode kick-off

In `:auto`, after `decompose!` flips to `:dispatching`, the orchestrator's next tick (or an explicit synchronous `dispatch!` after create) starts workers. In `:manual`, a "Start" button on the show page calls `dispatch!`.

**Files:**
- Modify: `app/controllers/swarm_missions_controller.rb` — `create` calls `@swarm_mission.dispatch_later` only when `mode == :auto`
- Modify: `app/views/swarm_missions/show.html.erb` — "Start mission" button visible only when state == `:dispatching`
- Create: `app/jobs/swarm/dispatch_job.rb`
- Create: `test/controllers/swarm_missions_dispatch_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class SwarmMissionsDispatchTest < ActionDispatch::IntegrationTest
    setup do
      Current.user = users(:one); sign_in_as users(:one); AgentProfile.refresh_from_yaml!
    end

    test "auto-mode mission enqueues DecompositionJob and DispatchJob on create" do
      assert_enqueued_with(job: Swarm::DecompositionJob) do
        assert_enqueued_with(job: Swarm::DispatchJob) do
          post swarm_missions_path,
               params: { swarm_mission: { title: "Auto", goal: "G", mode: "auto" } }
        end
      end
    end

    test "manual-mode mission enqueues decompose but not dispatch" do
      assert_enqueued_with(job: Swarm::DecompositionJob) do
        assert_no_enqueued_jobs only: Swarm::DispatchJob do
          post swarm_missions_path,
               params: { swarm_mission: { title: "Manual", goal: "G", mode: "manual" } }
        end
      end
    end
  end
  ```

- [ ] **Step 2: Job + controller updates.**

  `app/jobs/swarm/dispatch_job.rb`:

  ```ruby
  module Swarm
    class DispatchJob < ApplicationJob
      def perform(mission) = mission.dispatch!
    end
  end
  ```

  In `app/models/swarm_mission.rb` add:

  ```ruby
  def dispatch_later
    Swarm::DispatchJob.set(wait: 5.seconds).perform_later(self)
    # wait:5s = let decompose_later land first
  end
  ```

  In `SwarmMissionsController#create`, after `decompose_later`:

  ```ruby
  @swarm_mission.dispatch_later if @swarm_mission.auto?
  ```

- [ ] **Step 3: Run test.**

  ```
  bin/rails test test/controllers/swarm_missions_dispatch_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.20: Auto-mode dispatch wiring (DecompositionJob + DispatchJob) + manual-mode Start button
  ```

---

## Task 6.21 — Phase 3 carry-over: real `Message#available_tools` filter

Today's `Message::Streamable#available_tools` has a non-admin `run_shell` stop-gap and an empty `skill_tool_definitions`. Replace both with the proper filter:

1. `Tool::Internal.allowed_for(user)` — admin sees `run_shell`, others don't.
2. `Tool::Mcp.allowed_for(user)` — already user-scoped via `mcp_servers.user_id` (Phase 4).
3. For **non-swarm** chat sessions: tools from `Skill.enabled_for(user).flat_map(&:tool_definitions)`.
4. For **swarm worker** chat sessions (those tied to a `SwarmAssignment`): tools from `assignment.agent_profile.skills_for(user).flat_map(&:tool_definitions)`.

Each `Skill` needs a `#tool_definitions` method. For Phase 6 we keep the implementation simple: a skill defines its tools via a `tools:` array in its frontmatter, mapped to existing `Tool::Internal` definitions by name. If a skill has no `tools:` declared, it injects only a prompt section, no tools.

**Files:**
- Modify: `app/models/skill.rb` — add `#tool_definitions` reader using `manifest["tools"]`
- Modify: `app/models/message/streamable.rb` — replace stub `available_tools`, add `swarm_assignment` association lookup
- Modify: `app/models/chat_session.rb` — add `belongs_to :swarm_assignment, optional: true` (was added to migration in 6.4 via the assignment-side FK; this is the inverse association)
- Modify: `app/models/tool/internal.rb` — add `.allowed_for(user)` class method (current logic is in Streamable)
- Modify: `app/models/tool/mcp.rb` — confirm `.allowed_for(user)` exists; if not, add it as a thin wrapper over `all_definitions(user:)`
- Create: `test/models/message/available_tools_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class Message::AvailableToolsTest < ActiveSupport::TestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
    end

    # NOTE: `users(:one)` is admin (role: 1) per the fixture. Use `users(:two)`
    # for the non-admin assertion (added in Task 6.0 Step 4).
    test "non-admin chat session excludes run_shell" do
      Current.user = users(:two)
      chat = ChatSession.create!(user: users(:two), title: "T", model: "m", provider: "anthropic")
      msg = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                  model: "claude-sonnet-4-5", provider: "anthropic")
      assert chat.user.member?
      names = msg.available_tools.map { |t| t[:name] }
      refute_includes names, "run_shell"
    end

    test "admin chat session includes run_shell" do
      Current.user = users(:one)  # role: 1 = admin
      chat = ChatSession.create!(user: users(:one), title: "T", model: "m", provider: "anthropic")
      msg = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                  model: "claude-sonnet-4-5", provider: "anthropic")
      names = msg.available_tools.map { |t| t[:name] }
      assert_includes names, "run_shell"
    end

    test "swarm-worker chat session uses agent_profile.skills, not user.enabled_skills" do
      Current.user = users(:two)  # non-admin to keep the surface tight
      mission = SwarmMission.create!(user: users(:two), created_by: users(:two), title: "M", goal: "G")
      profile = AgentProfile.find_by!(slug: "backend")
      research = skills(:research)
      profile.skills << research
      research.install_for(users(:two)); research.enable_for(users(:two))
      asg = SwarmAssignment.create!(swarm_mission: mission, agent_profile: profile, task: "T")
      chat = ChatSession.create!(user: users(:two), title: "Worker", model: "m", provider: "anthropic",
                                 swarm_assignment: asg)
      msg = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                  model: "claude-sonnet-4-5", provider: "anthropic")
      # The skill defines no tools — assert it appears in system prompt but no tool def is added
      assert_match(/Skill: research/, msg.system_prompt)
    end
  end
  ```

- [ ] **Step 2: Implementation.**

  In `app/models/skill.rb`:

  ```ruby
  def tool_definitions
    Array(manifest["tools"]).filter_map { |tool_name|
      Tool::Internal.lookup(tool_name)&.tool_definition
    }
  end
  ```

  In `app/models/tool/internal.rb`:

  ```ruby
  def self.allowed_for(user)
    return all_definitions if user&.admin?
    all_definitions.reject { |d| d[:name] == "run_shell" }
  end
  ```

  In `app/models/tool/mcp.rb`:

  ```ruby
  def self.allowed_for(user)
    all_definitions(user: user)
  end
  ```

  Make the migration to add `swarm_assignment_id` to `chat_sessions`:

  ```bash
  bin/rails g migration AddSwarmAssignmentToChatSessions swarm_assignment:references
  ```

  Migration body:

  ```ruby
  class AddSwarmAssignmentToChatSessions < ActiveRecord::Migration[8.1]
    def change
      add_reference :chat_sessions, :swarm_assignment, foreign_key: true
    end
  end
  ```

  Update `app/models/chat_session.rb`:

  ```ruby
  belongs_to :swarm_assignment, optional: true
  ```

  Update `app/models/message/streamable.rb`'s `available_tools` + `skill_tool_definitions`:

  ```ruby
  def available_tools
    defs  = Tool::Internal.allowed_for(chat_session.user)
    defs += Tool::Mcp.allowed_for(chat_session.user)
    defs + enabled_skills.flat_map(&:tool_definitions)
  end

  def enabled_skills
    @enabled_skills ||= if chat_session.swarm_assignment
      chat_session.swarm_assignment.agent_profile.skills_for(chat_session.user).to_a
    else
      Skill.enabled_for(chat_session.user).to_a
    end
  end

  # Remove old `skill_tool_definitions(_skill)` stub.
  ```

- [ ] **Step 3: Migrate + run tests.**

  ```
  bin/rails db:migrate db:test:prepare
  bin/rails test test/models/message/available_tools_test.rb
  bin/rails test test/models/message  # full streamable suite stays green
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.21: Real Message#available_tools filter — per-user run_shell + per-skill tools + agent-profile skill scope for swarm chats
  ```

---

## Task 6.22 — Phase 5 carry-over: `Event.prune!` recurring sweeper

Phase 5 (Open items) flagged: `Event` rows grow unbounded. Add a recurring sweeper that drops `Event` rows older than 90 days, except those with `action LIKE '%_failed'` (retain failures longer for audit) — those drop after 365 days.

**Files:**
- Create: `app/jobs/event/prune_job.rb`
- Modify: `app/models/event.rb` (add `Event.prune!`)
- Modify: `config/recurring.yml` (add `event_prune` daily entry)
- Create: `test/models/event_prune_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class EventPruneTest < ActiveSupport::TestCase
    test "prune! deletes :info events older than 90 days; keeps failures up to 365 days" do
      old_info  = Event.create!(action: "skill_installed",       occurred_at: 100.days.ago, particulars: {})
      keep_info = Event.create!(action: "skill_installed",       occurred_at: 30.days.ago,  particulars: {})
      old_fail  = Event.create!(action: "skill_install_failed",  occurred_at: 400.days.ago, particulars: {})
      keep_fail = Event.create!(action: "skill_install_failed",  occurred_at: 200.days.ago, particulars: {})

      assert_difference -> { Event.count }, -2 do
        Event.prune!
      end
      refute Event.exists?(id: old_info.id)
      refute Event.exists?(id: old_fail.id)
      assert Event.exists?(id: keep_info.id)
      assert Event.exists?(id: keep_fail.id)
    end
  end
  ```

- [ ] **Step 2: Implementation.**

  Add to `app/models/event.rb`:

  ```ruby
  INFO_RETENTION_DAYS    = 90
  FAILURE_RETENTION_DAYS = 365

  def self.prune!
    info_cutoff    = INFO_RETENTION_DAYS.days.ago
    failure_cutoff = FAILURE_RETENTION_DAYS.days.ago
    transaction do
      where("occurred_at < ? AND action NOT LIKE ?", info_cutoff, "%_failed").delete_all
      where("occurred_at < ? AND action LIKE ?",     failure_cutoff, "%_failed").delete_all
    end
  end
  ```

  `app/jobs/event/prune_job.rb`:

  ```ruby
  class Event::PruneJob < ApplicationJob
    def perform = Event.prune!
  end
  ```

  `config/recurring.yml`:

  ```yaml
    event_prune:
      class: Event::PruneJob
      schedule: every day at 3am
  ```

- [ ] **Step 3: Run test.**

  ```
  bin/rails test test/models/event_prune_test.rb
  ```

  Expected: green.

- [ ] **Step 4: Commit.**

  ```
  Phase 6 Task 6.22: Event.prune! recurring sweeper (Phase 5 carry-over from workflows.md § 19 retention)
  ```

---

## Task 6.23 — End-to-end system test

Exercises the Phase 6 exit criteria: 2 workers spawn, conductor decomposes, kanban updates, checkpoints store, blocker surfaces.

**Files:**
- Create: `test/system/swarm_test.rb`

- [ ] **Step 1: System test.**

  ```ruby
  require "application_system_test_case"

  class SwarmTest < ApplicationSystemTestCase
    setup do
      Current.user = users(:one)
      AgentProfile.refresh_from_yaml!
      sign_in_as users(:one)
    end

    test "create mission → decompose → workers spawn → kanban shows live state → blocker surfaces" do
      skip "tmux missing" unless system("which tmux >/dev/null 2>&1")

      LlmStubs.with_decomposition({
        decomposition_notes: "Two-step plan",
        assignments: [
          { agent_slug: "backend",  task: "Build the model",  rationale: "Backend specialty", depends_on: [],     review_required: false },
          { agent_slug: "frontend", task: "Wire the UI",      rationale: "Frontend specialty", depends_on: [ 1 ], review_required: false }
        ]
      }) do
        visit new_swarm_mission_path
        fill_in "Title", with: "End-to-end test"
        fill_in "Goal",  with: "Ship the feature"
        choose "Auto"
        click_button "Create"

        # The DecompositionJob runs inline in :test (perform_now)
        Swarm::DecompositionJob.perform_now(SwarmMission.last)
        assert_text "Build the model"
        assert_text "Wire the UI"
      end

      mission = SwarmMission.last

      # Stub Swarm::TmuxBridge so we don't actually spawn tmux from a test
      # (the supervisor_v3_test covers the tmux path under a sandboxed
      # boot). Verify the orchestrator + view updates work end-to-end.
      Swarm::TmuxBridge.singleton_class.alias_method(:_real_spawn,  :spawn_worker)
      Swarm::TmuxBridge.singleton_class.alias_method(:_real_keys,   :send_keys)
      Swarm::TmuxBridge.singleton_class.alias_method(:_real_close,  :close_worker)
      Swarm::TmuxBridge.define_singleton_method(:spawn_worker) { |_| { tmux_session_name: "x", fifo: "/tmp/x" } }
      Swarm::TmuxBridge.define_singleton_method(:send_keys)    { |_a, _d| nil }
      Swarm::TmuxBridge.define_singleton_method(:close_worker) { |_| { ok: true } }
      mission.dispatch!

      # Simulate worker output containing a blocker
      first = mission.assignments.order(:id).first
      Swarm::OutputBuffer.singleton.instance_variable_get(:@buffers)[first.id] << <<~OUT
        ===HERMES CHECKPOINT===
        state_label: stuck
        runtime_state: {}
        files_changed: []
        commands_run: []
        result: null
        blocker: "Need credentials for the DB"
        next_action: null
        ===END CHECKPOINT===
      OUT
      mission.advance!

      visit swarm_mission_path(mission)
      assert_text "Blocker: Need credentials for the DB"
      assert_text "Backend Worker"

      visit swarm_kanban_path
      assert_text "Build the model"
    end
  end
  ```

- [ ] **Step 2: Run.**

  ```
  bin/rails test:system test/system/swarm_test.rb
  ```

  Expected: green (or skipped if tmux missing).

- [ ] **Step 3: Commit.**

  ```
  Phase 6 Task 6.23: End-to-end system test — create → decompose → dispatch → blocker → kanban
  ```

---

## Task 6.24 — Phase 6 exit criteria + verification

- [ ] **Spawn 2 swarm workers, give conductor a goal, watch decomposition, workers execute in tmux, kanban updates live, checkpoints record progress, blocked tasks await user input.** Covered by `test/system/swarm_test.rb` (Task 6.23) + `test/integration/supervisor_v3_test.rb` (Task 6.10).
- [ ] **Conductor decomposition is robust to malformed LLM output.** `test/models/swarm_mission/decomposable_test.rb` (Task 6.9).
- [ ] **SwarmCheckpoint parser skips malformed stanzas + handles blocker markers.** `test/models/swarm_checkpoint_test.rb` (Task 6.7).
- [ ] **State machine transitions only happen through explicit methods.** Code review: grep `update.*state:` outside concern files and assert all callers are inside transition methods.
- [ ] **Phase 3 carry-over closed.** `test/models/message/available_tools_test.rb` (Task 6.21) — admin/non-admin, swarm vs chat.
- [ ] **Phase 5 carry-over closed.** `Event.prune!` recurring entry shipped (Task 6.22).
- [ ] **Cross-tenancy on `/swarm/*` + `SwarmChannel`.** H1 (below).
- [ ] **All tests pass:**

  ```bash
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```

  Expected: tests green; brakeman = Phase 5 baseline + 0 new (every disk path through `WorkspacePath.resolve`, every shell call array-form `Open3`). Bundler-audit: 0 vulnerabilities. Record the new run/assertion totals — Phase 7 verification compares against these.

- [ ] **Tag `phase-6`.** `git tag phase-6` after the hardening gate closes.

---

## Phase 6 hardening gate (must-fix before tagging)

Mirrors the Phase 3 / 4 / 5 H-series structure. Predicted from this plan; refine after a 4-parallel-agent code review (Task 6.25-style follow-up batch).

- [ ] **H1 — Cross-tenancy on `/swarm/missions/*` + `SwarmChannel` + `/swarm/agents`.** User B subscribing to A's `SwarmChannel.stream_for(mission)` is rejected (Task 6.11 already tests this); `GET /swarm/missions/<a-id>` as B returns 404; `/swarm/agents` returns 403 for non-admin (Task 6.17 tests). Add the `CrossTenancyAssertions` sweep across `update`/`destroy`/`assignments#update`/`cancellations#create`.

- [ ] **H2 — Tmux session naming collisions.** `mop-swarm-<assignment-id>` is unique per assignment (DB-assigned PK). But terminal sessions use `mop-term-<id>` against `terminal_sessions.id` — disjoint table, no collision. Add an integration probe that creates an assignment with id 42 and a terminal_session with id 42 and asserts both tmux sessions coexist.

- [ ] **H3 — `Swarm::OutputBuffer` FIFO leak on assignment failure.** When `assignment.fail!` runs `close_worker`, the buffer's `@fifos[id]` IO handle is NOT closed; over a long-running supervisor this leaks file descriptors. `Dispatchable#fail!`/`complete!`/`cancel!` should call `Swarm::OutputBuffer.singleton.close(id)` after `close_worker`.

- [ ] **H4 — Conductor decomposition prompt size + cache budget.** With 8 profiles × 20 skills each, the decomposition prompt can exceed 50 KB. Cap rendered prompt at 16 KB; if over, truncate `enabled_skills` per profile to the top 10 (alphabetical) and add a note "...truncated".

- [ ] **H5 — `decompose!` is idempotent + abort-safe.** If `decompose!` crashes mid-loop after creating 1 of 5 assignments, the next retry doubles up. Solution: the transaction wrapping the whole `assignments.create!` loop already aborts cleanly — verify with a test that raises after assignment 2 and asserts 0 rows remain.

- [ ] **H6 — `SwarmAssignment.dispatch_ready` race.** Two orchestrator ticks could both see the same `ready` assignment and dispatch twice (the supervisor's idempotency would catch the second tmux create, but the DB would have two `state: :dispatched` writes). The orchestrator job uses `limits_concurrency to: 1, on_conflict: :discard` (Task 6.13) — verify with a test that enqueues two identical jobs and asserts only one runs.

- [ ] **H7 — `SwarmChannel` chunk-size + rate cap.** Like Phase 4 H5 for `TerminalChannel`: cap `chunk` at 64 KiB; a flood like `yes` in a worker must not flood Action Cable. Buffer 50 ms in `Swarm::OutputBuffer#drain` before broadcasting if chunk count > N.

- [ ] **H8 — `SwarmEvent` retention.** Like `Event` (Task 6.22), `SwarmEvent` grows unbounded. Add `SwarmEvent.prune!` (drop rows older than 30 days when the parent mission is `complete` or `cancelled`) + recurring entry.

- [ ] **H9 — Worker death detection.** If a tmux session terminates abnormally (`exit 1` from the worker), the supervisor doesn't notify Rails. Add a periodic check in `Swarm::OutputBuffer#drain` that asserts `tmux has-session -t mop-swarm-<id>` and flips the assignment to `:failed` if missing. Alternative: supervisor emits `swarm.worker_terminated` notification on tmux exit (cleaner — requires supervisor work).

- [ ] **H10 — `Dispatchable#kickoff_prompt` injection guard.** `task.text` is interpolated into the prompt. Worker prompt is sent via `tmux send-keys -l <data>` (literal-mode, array-form) which is safe, but an LLM-emitted `===HERMES CHECKPOINT===` inside the task text would confuse the parser. Strip occurrences of `===HERMES CHECKPOINT===` from `task` at validation time.

- [ ] **H11 — Manual-mode + auto-mode mid-mission toggle.** A user flips `:auto → :manual` while assignments are dispatching. The orchestrator must NOT auto-dispatch new ready assignments after the toggle. `Advanceable#transition_after_assignments` already checks `auto?` — add a test that flips mid-flight and asserts no further dispatch.

- [ ] **H12 — `decompose!` opens a hidden ChatSession every time.** Multiple retries leave orphan `ChatSession` rows. Either (a) reuse a single hidden session per mission (add `belongs_to :decomposition_chat_session, class_name: "ChatSession", optional: true`), or (b) accept the dead rows and rely on a future `ChatSession.prune!` recurring sweeper. Pick (a); cheaper at DB-row level and the decomposition history becomes inspectable.

---

## Task 6.25 — Post-review fix-ups (Phase 6 batch 2) — placeholder

After the hardening gate closes and `phase-6` is tagged, schedule a code review (4 parallel agents per Phase 3 / 4 / 5 pattern). Likely surface:

- `Swarm::OutputBuffer` thread-safety under SolidQueue worker fork.
- `decompose!` LLM cost — log token usage per call; expose on mission show.
- `SwarmCheckpoint.parse` ambiguity when state_label contains whitespace.
- `SwarmChannel` reconnect replay — the buffer doesn't have a cursor; a reconnecting client misses output that already drained.
- `AgentProfile` enable/disable transitions don't propagate to live workers (a profile disabled mid-mission should be allowed to finish but never accept a new assignment).
- The kanban Stimulus controller's drag/drop UX — only manually unblocks; document deferred manual transitions.

Land as 2–3 grouped commits mirroring 3.16a/b/c and 4.17.

---

## Phase 6.5 — Slip candidates (defer if scope balloons; exit criteria still hold)

1. **MCP stdio bridge** (re-slipped from 4.5). `Mcp::StdioBridge` + supervisor `mcp.spawn`/`mcp.invoke`/`mcp.shutdown` RPC handlers. Phase 6 exit criteria use only built-in tools + HTTP MCP. Stdio MCP becomes useful when workers need GitHub MCP or filesystem MCP.

2. **Multi-turn conductor refinement.** After all assignments resolve, the conductor reviews results via `app/services/conductor/prompts/review.erb` and may emit a follow-up assignment set (`mission.advance!` → `:reviewing` → either `:complete` or back to `:executing`).

3. **Per-user mission concurrency cap.** A user could create N missions × M assignments → tmux fan-out exhausts the host. Add `MOP_MAX_ACTIVE_MISSIONS_PER_USER` (default 3) gate at controller-level.

4. **Cost-budget auto-pause.** Each mission has a cost cap; when `sum(messages.cost_usd)` exceeds it, the next assignment's `dispatch!` is replaced with `block!(reason: "cost cap reached")`.

5. **Worker reconnect replay.** Mirror of Phase 4.5 "Action Cable cursor-replay-from-message" — a reconnecting browser misses output broadcast while disconnected. Solution: `SwarmChannel.subscribe(replay_from_assignment_checkpoint:)` re-broadcasts `SwarmCheckpoint`s since the cursor.

6. **Speech-to-text for block resolution.** A blocked assignment shows a "Speak the answer" button. Phase 7 has voice infra.

---

## Critical files map (Phase 6 additions)

```
config/routes.rb                                         # +swarm_missions, +swarm_kanban, +agent_profiles
config/recurring.yml                                     # +swarm_orchestrator, +event_prune
config/importmap.rb                                      # +sortablejs (kanban drag-drop)

db/migrate/<ts>_create_agent_profiles.rb
db/migrate/<ts>_create_agent_profile_skills.rb
db/migrate/<ts>_create_swarm_missions.rb
db/migrate/<ts>_create_swarm_assignments.rb
db/migrate/<ts>_create_swarm_mission_cancellations.rb
db/migrate/<ts>_create_swarm_events.rb
db/migrate/<ts>_create_swarm_checkpoints.rb
db/migrate/<ts>_add_swarm_assignment_to_chat_sessions.rb
db/seeds/agent_profiles.yml

app/models/agent_profile.rb
app/models/agent_profile/loadable.rb
app/models/agent_profile_skill.rb
app/models/swarm_mission.rb
app/models/swarm_mission/cancellable.rb
app/models/swarm_mission/cancellation.rb
app/models/swarm_mission/decomposable.rb
app/models/swarm_mission/advanceable.rb
app/models/swarm_assignment.rb
app/models/swarm_assignment/dispatchable.rb
app/models/swarm_event.rb
app/models/swarm_checkpoint.rb
app/models/chat_session.rb                               # +belongs_to :swarm_assignment, optional: true
app/models/skill.rb                                      # +tool_definitions
app/models/event.rb                                      # +prune!
app/models/tool/internal.rb                              # +allowed_for(user)
app/models/tool/mcp.rb                                   # +allowed_for(user)
app/models/message/streamable.rb                         # replace stub available_tools + enabled_skills

app/services/conductor.rb
app/services/conductor/prompts.rb
app/services/conductor/prompts/decomposition.erb
app/services/swarm/tmux_bridge.rb
app/services/swarm/output_buffer.rb

app/channels/swarm_channel.rb

app/jobs/swarm/decomposition_job.rb
app/jobs/swarm/dispatch_job.rb
app/jobs/swarm/orchestrator_loop_job.rb
app/jobs/event/prune_job.rb

app/controllers/concerns/swarm_mission_scoped.rb
app/controllers/swarm_missions_controller.rb
app/controllers/swarm_missions/assignments_controller.rb
app/controllers/swarm_missions/cancellations_controller.rb
app/controllers/swarm_kanbans_controller.rb
app/controllers/agent_profiles_controller.rb
app/controllers/agent_profile_syncs_controller.rb

app/views/swarm_missions/{index,show,new,_form,_mission_row,_assignment,_event_feed}.html.erb
app/views/swarm_kanbans/show.html.erb
app/views/agent_profiles/{index,show,new,edit,_form}.html.erb

app/javascript/controllers/swarm_channel_controller.js
app/javascript/controllers/kanban_controller.js
app/javascript/controllers/index.js                      # register both controllers

bin/agents_supervisor                                    # v3: swarm.* handlers + SwarmTmuxBridge

test/fixtures/agent_profiles.yml
test/fixtures/agent_profile_skills.yml
test/fixtures/swarm_missions.yml
test/fixtures/swarm_assignments.yml
test/fixtures/swarm_mission_cancellations.yml
test/fixtures/swarm_events.yml
test/fixtures/swarm_checkpoints.yml
test/models/agent_profile_test.rb
test/models/agent_profile/loadable_test.rb
test/models/agent_profile_skill_test.rb
test/models/swarm_mission_test.rb
test/models/swarm_mission/cancellable_test.rb
test/models/swarm_mission/decomposable_test.rb
test/models/swarm_mission/advanceable_test.rb
test/models/swarm_mission/dispatch_test.rb
test/models/swarm_assignment_test.rb
test/models/swarm_assignment/dispatchable_test.rb
test/models/swarm_event_test.rb
test/models/swarm_checkpoint_test.rb
test/models/message/available_tools_test.rb
test/models/event_prune_test.rb
test/channels/swarm_channel_test.rb
test/services/conductor/prompts_test.rb
test/services/swarm/tmux_bridge_test.rb
test/services/swarm/output_buffer_test.rb
test/jobs/swarm/decomposition_job_test.rb
test/jobs/swarm/orchestrator_loop_job_test.rb
test/controllers/swarm_missions_controller_test.rb
test/controllers/swarm_missions/cancellations_controller_test.rb
test/controllers/swarm_missions_dispatch_test.rb
test/controllers/swarm_missions_mode_toggle_test.rb
test/controllers/swarm_kanbans_controller_test.rb
test/controllers/agent_profiles_controller_test.rb
test/integration/supervisor_v3_test.rb
test/system/swarm_test.rb
```

---

## Open items (Phase 6 only — surface as you hit them, don't pre-decide)

- **Worker death notification path.** Today the supervisor doesn't proactively notify Rails when a `mop-swarm-<id>` session exits abnormally. The orchestrator's `Swarm::OutputBuffer#drain` could `tmux has-session` to detect, but that's 1 process-spawn per assignment per tick. If H9 turns into a hot path, push notification onto the supervisor side (`swarm.worker_terminated`). Don't pre-decide.

- **Auto-dispatch concurrency.** `SwarmAssignment.dispatch_ready` dispatches all ready assignments in a tick. With high-fanout decomposition this could spawn 5+ tmux sessions per tick — fine on dev laptops, but a prod box with many missions could thrash. If observed, add `MAX_CONCURRENT_WORKERS_PER_MISSION` (default unlimited).

- **`Conductor::Prompts.decomposition` skill rollup.** Today: per profile, list `skills_for(user)`. If a user has 100 skills installed, the prompt balloons. Workaround in H4. A better long-term fix is to pre-summarize skill kits server-side. Don't pre-build.

- **`SwarmMission#decomposition_chat_session`** (per H12). Pick a foreign-key column name; whether to keep these sessions visible in `/chat` is a UX call (default: hide via a `hidden:boolean` flag). Surface this when implementing H12.

- **MCP stdio for swarm workers** — the deferred Phase 4.5 work. The Phase 6 exit criteria don't depend on it, but real-world swarm work often does (e.g. GitHub MCP for PR review). Surface as a Phase 7 candidate if 6.5 doesn't land.

- **Decomposition cost visibility.** Today: not exposed. Each mission show page should display `decomposition_chat_session.cost_usd` once H12 lands; surface if operators ask.

- **State enum cardinality grew large.** `SwarmMission.state` has 7 values, `SwarmAssignment.state` has 7. A swarm UI that wants to render "all-states pie chart" must update if values change. Centralize the human-readable list in `app/helpers/swarm_helper.rb` (Phase 7 polish).

- **`AgentProfile#status` does NOT currently transition.** The `online/away/offline` column is in the schema but never written. Phase 6 leaves it as static (operator edits via UI). Wiring `status: :online` on first `swarm.spawn_worker` + `:offline` on last `swarm.close_worker` is a small follow-up.

---

## Decisions logged during Phase 6 planning

These look like open questions but were closed during this plan — not deferred, decided.

- **`SwarmEvent` is NOT polymorphic Eventable.** Workflows.md:139 explicitly distinguishes them; we keep two tables (audit vs telemetry) and explicitly comment the distinction at the top of `SwarmEvent`.

- **`SwarmMission::Cancellable` uses a child-table (`swarm_mission_cancellations`), not an enum value.** Workflows.md:155 lists it as a `resource :cancellation` route, and the table is in the migration list — consistent with `chat_session_archives` / `scheduled_job_pauses`.

- **State transitions are explicit methods.** Never `update!(state: :X)` from a controller; always go through `dispatch!`, `advance!`, `block!`, `complete!`, `fail!`, `cancel!`, `unblock!`. The `update :mode` exception (mode is a config toggle, not a state machine) is enforced by writing tests against direct enum flips in controllers (H11).

- **One supervisor per assignment, not per profile.** Workflows.md:3058 says "per-profile tmux session for each swarm worker", which on closer reading means "per assignment's profile". An assignment IS the unit of work — different assignments go to different worker tmux sessions, even when the same profile gets two assignments concurrently.

- **Recurring orchestrator + `limits_concurrency to:1, on_conflict: :discard`.** Mirrors Phase 5 H10. Two ticks colliding → one runs, the other discards (next tick picks up). Cheap protection.

- **Checkpoint marker format = YAML between fixed sentinels.** Alternative was JSON or a custom DSL. YAML wins because workers can emit multi-line strings (`result: |`) and `Psych.safe_load` is sufficiently sandboxed (no permitted classes).

- **`auto`/`manual` is a column on the mission, not a child row.** It's a config toggle, not an event — no audit value in tracking "when did mode flip". A simple integer enum is enough.

- **Conductor decompose target model = the first enabled `AgentProfile`'s model + provider.** Alternative was a separate `conductor_model` column; deferred until the operator wants to pick (Phase 7).

- **Tmux session prefix = `mop-swarm-<assignment-id>`** (vs `mop-swarm-<profile-slug>-<mission-id>`). The assignment_id is unique and short; collisions impossible. Keeps tmux names short for `tmux list-sessions` readability.

---

## Self-review checklist (planning)

- [x] **Spec coverage** — every workflows.md § Phase 6 deliverable maps to a task above (or is explicitly Phase 6.5):
  - 7 migrations → Tasks 6.1–6.7
  - Agent profile seed → Task 6.1
  - AgentProfile page + Roster → Task 6.17
  - `SwarmMission::Decomposable#decompose!` → Task 6.9
  - `SwarmAssignment.dispatch_ready` → Task 6.12
  - `Swarm::OrchestratorLoopJob` recurring 30s → Task 6.13
  - `SwarmCheckpoint.parse(raw)` → Task 6.7
  - Supervisor v3 per-profile tmux → Task 6.10
  - Swarm pages (missions list/detail/kanban/worker chat/event log) → Tasks 6.15, 6.16, 6.18
  - Auto/manual toggle → Tasks 6.19, 6.20
  - Phase 3 carry-over (`available_tools` filter) → Task 6.21
- [x] **Phase carryovers explicit** — Phase 3 (6.21), Phase 4.5 (Phase 6.5 slip #1), Phase 5 (6.22).
- [x] **Phase 5 epilogue acknowledged** — Task 6.0 tags `phase-5` at `5e7269a` before any new code.
- [x] **Concrete file paths** — every task names the file it touches.
- [x] **Failing test first** — each task starts from a red test, not from an implementation sketch.
- [x] **Verification commands present** — every task ends with a runnable assertion + expected output.
- [x] **Hardening gate predicted** — 12 items that mirror Phase 3 / 4 / 5 H1–H12.
- [x] **Open items separate from decisions** — Phase 6 open items list, plus a "Decisions logged" section that pre-empts revisiting.
- [x] **Scope budget realistic** — 25 tasks (6.0–6.24) for a 3–4 week phase, plus the hardening gate and slip-candidate carve-out (6.5).
- [x] **Cross-tenancy** — H1 calls out the full sweep across `/swarm/*` + `SwarmChannel` + `/swarm/agents`.
- [x] **State-change child tables** — `swarm_mission_cancellations` follows the `chat_session_archives` / `scheduled_job_pauses` pattern (Task 6.5).
- [x] **No interpolated SQL** — every `where` uses bound parameters. `SwarmCheckpoint.parse` uses `Psych.safe_load` with empty `permitted_classes` (no class instantiation).
- [x] **3-line jobs preserved** — `DecompositionJob`, `DispatchJob`, `OrchestratorLoopJob`, `Event::PruneJob` are all single-method `def perform = ...` wrappers per workflows § 10.
- [x] **State transitions are explicit methods** — never `update.*state:` from controllers. H6 + H11 enforce.
- [x] **Eventable used** for audit (low-volume), `SwarmEvent` used for telemetry (high-volume) — distinction commented at top of `SwarmEvent`.
- [x] **MCP stdio dependency surfaced** — not blocking Phase 6 exit criteria; flagged in 6.5 slip candidates.
