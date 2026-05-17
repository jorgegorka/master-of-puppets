# Phase 5 — Scheduled Jobs + Dashboard

> **Executor:** Use `superpowers:subagent-driven-development` (or `superpowers:executing-plans`) to drive these tasks one at a time. Each `- [ ]` step has file paths, a failing test, the minimal impl, the verification command + expected output, and a commit. Tick the box as you complete each step.

**Parent plan:** [`docs/plans/workflows.md`](workflows.md) § Phase 5 (lines 3028–3044); domain model § 4 (105–224); routes § 9 (530–627); background jobs § 10 (631–712); real-time channels § 8 (501–528).

**Predecessors:** Phase 4 shipped at tag `phase-4` (commit `327c77d`). Three follow-up commits landed on top — `c229b0e` ("Fix issues."), `46eb415` ("More security fixes."), `fa1f923` ("Rubocop."). They harden the supervisor v2 + MCP boundary (added `MCP_SERVER_SCOPED` concern, tightened `Mcp::OutboundGuard`, expanded `Message::Streamable` MCP arm, dialed up brakeman ignore). Phase 5 starts from `HEAD == fa1f923` with a clean working tree.

**Goal:** the chat tool loop runs on a schedule and the operator sees what's happening. A user creates a cron-scheduled prompt at `/jobs`, the scheduler fires it every minute, `ScheduledJob#run!` spins up a chat session and captures the output as a `JobRun` row, the operator opens `/dashboard` and sees token/cost rollups, recent runs, MCP health, and an incident feed (`Event.where("action LIKE 'error_%'")`).

**Adds (high level):**

- `scheduled_jobs`, `job_runs`, `scheduled_job_pauses` migrations on `primary`.
- `ScheduledJob` model composing `Eventable` + `Pausable` (with `ScheduledJob::Pause` child). `JobRun` model with `Eventable`.
- `ScheduledJob::Cron` value object wrapping `fugit` (already in Gemfile from Phase 1). Computes `next_run_at` and rejects unbounded schedules (every-second tick).
- `SchedulerTickJob` (recurring 1 min) → `ScheduledJob.run_all_due` → enqueues `ScheduledJob::RunnerJob` per due job. All three are 3-line wrappers per workflows § 10.
- `ScheduledJob#run!` — opens a fresh `ChatSession`, posts a user message with the prompt, runs `Message#advance!` synchronously, captures cost/tokens/output into a new `JobRun` row, fires `Event` rows on succeed/fail. Bounded output size (`MAX_JOB_RUN_OUTPUT_BYTES`) overflows to the workspace.
- `ScheduledJobsController` (CRUD), `ScheduledJobs::PausesController` (pause/resume via singular `resource :pause`), `ScheduledJobs::RunsController` (index/show/create-for-manual-run). `ScheduledJobScoped` concern mirrors `ChatSessionScoped`.
- Jobs UI: list, new/edit form with cron-string preview, show with run history, run detail view.
- `JobsChannel` (`stream_for scheduled_job`) — live status broadcast on each `JobRun` status flip.
- `Event.incidents` scope (drops `:reloaded` events where `creator: nil`, surfaces `action LIKE 'error_%'`).
- `Dashboard::Rollup` PORO — token/cost rollups grouped by day, session, model. Reads from `messages` index on `chat_session_id, created_at` (Phase 1).
- `DashboardController#show` + view with chart.js charts (token spend per day, per model), recent runs, MCP server status table, incident feed.
- `DashboardChannel` (`stream "dashboard"`) — rebroadcasts on `JobRun`, `Message` finalize, `McpServer` status change.
- **Phase 3 carry-overs (workflows.md:3037–3042):**
  - FTS prefix-search upgrade — `prefix='2 3'` on `skills_fts` + `memory_files_fts` content migration, append `*` in `Searchable#matching`, ship `autocomplete_controller.js` for `/skills`. (Task 5.2.)
  - Lift `reindex_fts!` / `clear_fts_entry!` raw SQL out of `Skill::Loadable` and `MemoryFile::Reindexable` into a single `Searchable` adapter. (Task 5.1.)
  - Decide on `SkillInstallation#accepted_at` / `SkillEnablement#enabled_at` — both columns are dead weight (they always equal `created_at`). Drop both columns + the assignments. (Task 5.4.)
  - `:reloaded` events with `creator: nil` (watcher / boot-replay path) are filtered out of `Event.incidents`. (Task 5.17.)
  - Live `/skills` updates — `Skill#after_commit { broadcast_replace_to ... }` plus a `<turbo-cable-stream-source>` in `/skills`. (Task 5.3.) The dashboard reuses the same Turbo Stream infra in Task 5.18.

**Exit criteria:** see Task 5.19.

---

## Task 5.0 — Phase 4 epilogue + Phase 5 baseline

Phase 4 closed at tag `phase-4` (`327c77d`). Three security-cleanup commits (`c229b0e`, `46eb415`, `fa1f923`) landed on top — they harden MCP outbound guards, scope mcp_servers actions, and apply rubocop. Phase 5 starts from `HEAD == fa1f923` (workflow tree clean). Before writing any new code, pin the baseline so a regression doesn't get blamed on Phase 5.

- [ ] **Step 1: Confirm clean tree at `fa1f923`.**

  ```bash
  git status
  git log --oneline phase-4..HEAD
  git tag --list 'phase-*'
  ```

  Expected: working tree clean; three commits since `phase-4`; tags include `phase-2`, `phase-2-final`, `phase-3`, `phase-4`.

- [ ] **Step 2: Green test baseline before any Phase 5 code.**

  ```bash
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```

  Expected: tests green. Pin the run/assertion counts in your scratchpad (Phase 4 baseline reported `377 runs / 1035 assertions / 0 failures` + `7 system / 22`; the security cleanup commits will have bumped these — record the new numbers, not the Phase 4 ones). Brakeman: count = baseline + 0 new (the existing `config/brakeman.ignore` covers the MCP/Session paths). Bundler-audit: 0 vulnerabilities. Task 5.19 compares against this baseline, not against the workflows.md doc.

- [ ] **Step 3: No commit.** This task is a sanity check; nothing changed.

---

## Task 5.1 — Lift `reindex_fts!` / `clear_fts_entry!` into `Searchable`

Phase 3 left FTS-write raw SQL inside `Skill::Loadable` (`app/models/skill/loadable.rb:97–116`) and `MemoryFile::Reindexable` (`app/models/memory_file/reindexable.rb:84–102`) — workflows.md:3039 calls this out. Two near-identical chunks of `connection.execute(sanitize_sql([ … ]))` against `*_fts` virtual tables. Phase 5 lifts them into `Searchable` so the prefix-search work (Task 5.2) and any future FTS columns land in one place.

**Files:**
- Modify: `app/models/concerns/searchable.rb`
- Modify: `app/models/skill/loadable.rb`
- Modify: `app/models/memory_file/reindexable.rb`
- Test: `test/models/concerns/searchable_test.rb` (new)

- [ ] **Step 1: Write the failing test.**

  `test/models/concerns/searchable_test.rb`:

  ```ruby
  require "test_helper"

  class SearchableTest < ActiveSupport::TestCase
    test "Skill.reindex_fts_entry! writes a single row and clear_fts_entry! removes it" do
      skill = skills(:filesystem)
      skill.clear_fts_entry!
      assert_equal 0, SkillFts.where(skill_id: skill.id).count

      skill.reindex_fts_entry!(slug: skill.slug, name: skill.name, category: skill.category,
                               description: skill.description.to_s, body: "alpha bravo")
      assert_equal 1, SkillFts.where(skill_id: skill.id).count
      assert_includes SkillFts.where(skill_id: skill.id).pluck(:body), "alpha bravo"
    end

    test "MemoryFile.reindex_fts_entry! writes a single row keyed by memory_file_id" do
      file = memory_files(:one)
      file.clear_fts_entry!
      file.reindex_fts_entry!(path: file.path, title: file.title.to_s, tags: Array(file.tags).join(" "), body: "lorem ipsum")
      assert_equal 1, MemoryFileFts.where(memory_file_id: file.id).count
    end
  end
  ```

  Run: `bin/rails test test/models/concerns/searchable_test.rb -v`
  Expected: FAIL — `NoMethodError: undefined method 'reindex_fts_entry!'`.

- [ ] **Step 2: Add `searchable_via` columns declaration + the two helpers.**

  Replace `app/models/concerns/searchable.rb` body with:

  ```ruby
  module Searchable
    extend ActiveSupport::Concern

    class_methods do
      attr_reader :fts_class, :fts_foreign_key, :fts_columns

      # `columns:` is the ordered list of column names on the FTS table that
      # are populated on each write — same order as the INSERT.
      def searchable_via(fts_class, foreign_key:, columns:)
        @fts_class       = fts_class
        @fts_foreign_key = foreign_key
        @fts_columns     = columns
      end

      def matching(query)
        return [] if query.blank?
        raise "searchable_via not declared on #{self.name}" unless fts_class

        sanitized  = query.to_s.gsub('"', '""')
        table      = connection.quote_table_name(fts_class.table_name)
        ranked_ids = fts_class
          .where("#{table} MATCH ?", "\"#{sanitized}\"")
          .order(Arel.sql("bm25(#{table})"))
          .limit(50)
          .pluck(fts_foreign_key)
        return [] if ranked_ids.empty?

        rows = where(id: ranked_ids).index_by(&:id)
        ranked_ids.filter_map { |id| rows[id] }
      end
    end

    def reindex_fts_entry!(**values)
      cols     = self.class.fts_columns
      raise "searchable_via columns: missing on #{self.class.name}" unless cols

      fk       = self.class.fts_foreign_key
      fts      = self.class.fts_class
      table    = fts.connection.quote_table_name(fts.table_name)
      conn     = fts.connection

      values   = values.symbolize_keys
      missing  = cols - values.keys
      raise ArgumentError, "reindex_fts_entry! missing #{missing}" if missing.any?

      placeholders = (["?"] * (cols.length + 1)).join(", ")
      conn.execute(ActiveRecord::Base.sanitize_sql([ "DELETE FROM #{table} WHERE #{fk} = ?", id ]))
      conn.execute(ActiveRecord::Base.sanitize_sql([
        "INSERT INTO #{table} (#{fk}, #{cols.join(', ')}) VALUES (#{placeholders})",
        id, *cols.map { |c| values.fetch(c) }
      ]))
    end

    def clear_fts_entry!
      fts   = self.class.fts_class
      fk    = self.class.fts_foreign_key
      table = fts.connection.quote_table_name(fts.table_name)
      fts.connection.execute(ActiveRecord::Base.sanitize_sql([ "DELETE FROM #{table} WHERE #{fk} = ?", id ]))
    end
  end
  ```

- [ ] **Step 3: Wire `Skill` to the new API.**

  In `app/models/skill.rb`, replace `searchable_via SkillFts, foreign_key: :skill_id` with:

  ```ruby
  searchable_via SkillFts, foreign_key: :skill_id,
                 columns: %i[slug name category description body]
  ```

  In `app/models/skill/loadable.rb`, delete the `reindex_fts!` and `clear_fts_entry!` methods (lines 97–116). Replace the `flush_fts_write` body's call from `reindex_fts!(body)` with:

  ```ruby
  def flush_fts_write
    body = @pending_fts_body
    return unless body
    @pending_fts_body = nil
    reindex_fts_entry!(slug: slug, name: name, category: category,
                       description: description.to_s, body: body)
  rescue ActiveRecord::StatementInvalid
    update_columns(body_digest: "")
    raise
  end
  ```

- [ ] **Step 4: Wire `MemoryFile`.**

  Add to `app/models/memory_file.rb` after the other `include`s:

  ```ruby
  include Searchable
  searchable_via MemoryFileFts, foreign_key: :memory_file_id,
                 columns: %i[path title tags body]
  ```

  In `app/models/memory_file/reindexable.rb`, delete `reindex_fts_row!` (lines 84–96) and `clear_fts_entry!` (lines 100–105). Update `flush_fts_write`:

  ```ruby
  def flush_fts_write
    body = @pending_fts_body
    return unless body
    @pending_fts_body = nil
    reindex_fts_entry!(path: path, title: title.to_s, tags: Array(tags).join(" "), body: body)
  rescue ActiveRecord::StatementInvalid
    update_columns(content_digest: "")
    raise
  end
  ```

- [ ] **Step 5: Run the full FTS suite — nothing else should regress.**

  ```bash
  bin/rails test test/models/concerns/searchable_test.rb \
                 test/models/skill_test.rb \
                 test/models/skill_search_test.rb \
                 test/models/memory_file/reindexable_test.rb \
                 test/models/memory_file_test.rb
  ```

  Expected: all green.

- [ ] **Step 6: Commit.**

  ```bash
  git add app/models/concerns/searchable.rb \
          app/models/skill.rb \
          app/models/skill/loadable.rb \
          app/models/memory_file.rb \
          app/models/memory_file/reindexable.rb \
          test/models/concerns/searchable_test.rb
  git commit -m "Phase 5 Task 5.1: lift FTS writes into Searchable (concern owns reindex_fts_entry! + clear_fts_entry!)"
  ```

---

## Task 5.2 — FTS prefix-search upgrade

Phase 3 carry-over (workflows.md:3038). Today `Searchable#matching` wraps the query in `"…"` for a phrase match — typing `tal` finds nothing until the user types `talent`. The fix is two-part: (1) add `prefix='2 3'` to the FTS5 table so a 2-char or 3-char prefix is indexed; (2) append `*` to the last token in `#matching` so the FTS5 query treats it as a prefix.

**Files:**
- Create: `db/content_migrate/<ts>_add_prefix_to_fts_tables.rb`
- Modify: `app/models/concerns/searchable.rb`
- Create: `app/javascript/controllers/autocomplete_controller.js`
- Modify: `app/views/skills/index.html.erb`
- Test: `test/models/skill_search_test.rb` extension

- [ ] **Step 1: Failing prefix test.**

  Add to `test/models/skill_search_test.rb`:

  ```ruby
  test "matching returns rows for a 2-char prefix" do
    skill = skills(:filesystem)
    skill.update!(name: "Filesystem", description: "Read and write files")
    skill.reindex_fts_entry!(slug: skill.slug, name: "Filesystem",
                             category: skill.category, description: "Read and write files", body: "")

    assert_includes Skill.matching("fi"), skill, "2-char prefix should hit"
    assert_includes Skill.matching("file"), skill
  end
  ```

  Run: `bin/rails test test/models/skill_search_test.rb -v`
  Expected: FAIL — 2-char prefix returns no rows because the FTS table doesn't index 2-char prefixes.

- [ ] **Step 2: Content migration adds `prefix='2 3'` to both tables.**

  ```bash
  bin/rails g migration AddPrefixToFtsTables --database=content
  ```

  Edit `db/content_migrate/<ts>_add_prefix_to_fts_tables.rb`:

  ```ruby
  class AddPrefixToFtsTables < ActiveRecord::Migration[8.1]
    SKILLS_COLS  = "skill_id UNINDEXED, slug, name, category, description, body".freeze
    MEMORY_COLS  = "memory_file_id UNINDEXED, path, title, tags, body".freeze

    def up
      rebuild("skills_fts", SKILLS_COLS, key: "skill_id")
      rebuild("memory_files_fts", MEMORY_COLS, key: "memory_file_id")
    end

    def down
      rebuild("skills_fts", SKILLS_COLS, key: "skill_id", with_prefix: false)
      rebuild("memory_files_fts", MEMORY_COLS, key: "memory_file_id", with_prefix: false)
    end

    private
      def rebuild(table, cols, key:, with_prefix: true)
        cols_no_unindexed = cols.gsub(" UNINDEXED", "")
        plain_keys        = cols_no_unindexed.split(", ").map(&:strip).join(", ")
        execute "ALTER TABLE #{table} RENAME TO #{table}_old"
        prefix_clause = with_prefix ? ", prefix='2 3'" : ""
        execute <<~SQL
          CREATE VIRTUAL TABLE #{table} USING fts5(
            #{cols},
            tokenize = 'porter'#{prefix_clause}
          )
        SQL
        execute "INSERT INTO #{table} (#{plain_keys}) SELECT #{plain_keys} FROM #{table}_old"
        execute "DROP TABLE #{table}_old"
      end
  end
  ```

  Run: `bin/rails db:migrate`
  Expected: migration applies to `content` DB. Verify with `bin/rails dbconsole content -e 'pragma table_xinfo(skills_fts);'` — the schema should now show the `prefix='2 3'` option (via `sqlite_master`).

  Verify the `content_schema.rb` updated:

  ```bash
  grep -A1 "skills_fts\|memory_files_fts" db/content_schema.rb
  ```

  Expected: the `create_virtual_table` blocks now include `"prefix='2 3'"`.

- [ ] **Step 3: Append `*` to the last token in `Searchable#matching`.**

  In `app/models/concerns/searchable.rb`, replace the `matching` body:

  ```ruby
  def matching(query)
    return [] if query.blank?
    raise "searchable_via not declared on #{self.name}" unless fts_class

    # `tok1 tok2…` → `"tok1" "tok2"*` so the user's last (partial) token
    # is treated as a prefix. Each token is double-quoted to neutralise
    # FTS5 operator characters (AND, OR, NEAR, parens, `-`).
    tokens = query.to_s.scan(/[\p{Alnum}_]+/)
    return [] if tokens.empty?
    last   = tokens.pop
    quoted = tokens.map { |t| %("#{t.gsub('"', '""')}") }
    quoted << %("#{last.gsub('"', '""')}"*)
    expr   = quoted.join(" ")

    table      = connection.quote_table_name(fts_class.table_name)
    ranked_ids = fts_class
      .where("#{table} MATCH ?", expr)
      .order(Arel.sql("bm25(#{table})"))
      .limit(50)
      .pluck(fts_foreign_key)
    return [] if ranked_ids.empty?

    rows = where(id: ranked_ids).index_by(&:id)
    ranked_ids.filter_map { |id| rows[id] }
  end
  ```

  Run: `bin/rails test test/models/skill_search_test.rb -v`
  Expected: PASS — both 2-char and 4-char prefix hits.

- [ ] **Step 4: Autocomplete Stimulus controller.**

  Create `app/javascript/controllers/autocomplete_controller.js`:

  ```js
  import { Controller } from "@hotwired/stimulus"

  // Wires an <input> to a Turbo Frame whose `src` updates as the user types,
  // so /skills?q=<query> renders into the frame inline. 200ms debounce.
  export default class extends Controller {
    static values = { url: String, frame: String, debounce: { type: Number, default: 200 } }

    connect() { this._timer = null }
    disconnect() { clearTimeout(this._timer) }

    update(event) {
      clearTimeout(this._timer)
      this._timer = setTimeout(() => this.#submit(event.target.value), this.debounceValue)
    }

    #submit(value) {
      const frame = document.getElementById(this.frameValue)
      if (!frame) return
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("q", value)
      frame.src = url.toString()
    }
  }
  ```

  In `app/views/skills/index.html.erb`, wrap the existing search input + results in a Turbo Frame and add the controller wiring (preserve the existing markup):

  ```erb
  <input type="search"
         placeholder="Search skills…"
         data-controller="autocomplete"
         data-autocomplete-url-value="<%= skills_path %>"
         data-autocomplete-frame-value="skill-results"
         data-action="input->autocomplete#update"
         value="<%= @query %>">

  <%= turbo_frame_tag "skill-results" do %>
    <!-- existing list of @skills -->
  <% end %>
  ```

  Update `SkillsController#index` to respond to a Turbo Frame request:

  ```ruby
  def index
    @query  = params[:q].to_s
    @skills = @query.present? ? Skill.matching(@query) : Skill.all.order(:category, :name)
  end
  ```

  (no controller change beyond wrapping; Turbo Frame matching is automatic.)

- [ ] **Step 5: System test the autocomplete flow.**

  Add to `test/system/skills_test.rb`:

  ```ruby
  test "typing a 2-char prefix narrows the skill list" do
    sign_in_as users(:one)
    visit skills_path
    within("turbo-frame#skill-results") { assert_text "Filesystem" }
    fill_in "Search skills…", with: "fi"
    within("turbo-frame#skill-results") { assert_text "Filesystem" }
  end
  ```

  Run: `bin/rails test:system test/system/skills_test.rb -v`
  Expected: PASS.

- [ ] **Step 6: Commit.**

  ```bash
  git add db/content_migrate/<ts>_add_prefix_to_fts_tables.rb \
          db/content_schema.rb \
          app/models/concerns/searchable.rb \
          app/javascript/controllers/autocomplete_controller.js \
          app/views/skills/index.html.erb \
          test/models/skill_search_test.rb \
          test/system/skills_test.rb
  git commit -m "Phase 5 Task 5.2: FTS prefix search (prefix='2 3' + last-token-* + autocomplete controller)"
  ```

---

## Task 5.3 — Live `/skills` updates via Turbo Streams

Phase 3 carry-over (workflows.md:3042). When the supervisor's skills watcher fires a `Skill::ReloadJob`, the row updates server-side but `/skills` requires a refresh. Wire `Skill#after_commit { broadcast_replace_to "skills" }` and add a `<turbo-cable-stream-source channel="skills">` to the index — the dashboard reuses the same pattern in Task 5.18.

**Files:**
- Modify: `app/models/skill.rb`
- Create: `app/channels/skills_channel.rb`
- Modify: `app/views/skills/index.html.erb`
- Modify: `app/views/skills/_skill.html.erb` (extract from `index.html.erb` if needed)
- Test: `test/channels/skills_channel_test.rb`
- Test: `test/models/skill_broadcast_test.rb`

- [ ] **Step 1: Failing model test — assert a stream broadcast on `update`.**

  `test/models/skill_broadcast_test.rb`:

  ```ruby
  require "test_helper"

  class SkillBroadcastTest < ActionCable::Channel::TestCase
    test "Skill#update broadcasts a turbo_stream replace to 'skills'" do
      skill = skills(:filesystem)
      assert_broadcasts("skills", 1) do
        skill.update!(name: "Filesystem v2")
      end
    end
  end
  ```

  Run: `bin/rails test test/models/skill_broadcast_test.rb -v`
  Expected: FAIL — no broadcast.

- [ ] **Step 2: Add the broadcast.**

  In `app/models/skill.rb`, append:

  ```ruby
  # Skills change either by user action (install/enable, reload from /skills/:id)
  # or by the supervisor watcher firing Skill::ReloadJob. Turbo broadcasts
  # surface both in /skills without a refresh.
  after_commit -> { broadcast_replace_to "skills", target: ActionView::RecordIdentifier.dom_id(self), partial: "skills/skill", locals: { skill: self } }, on: %i[create update]
  after_commit -> { broadcast_remove_to  "skills", target: ActionView::RecordIdentifier.dom_id(self) }, on: :destroy
  ```

  Run: `bin/rails test test/models/skill_broadcast_test.rb -v`
  Expected: PASS.

- [ ] **Step 3: SkillsChannel auth.**

  Create `app/channels/skills_channel.rb`:

  ```ruby
  class SkillsChannel < ApplicationCable::Channel
    def subscribed
      stream_from "skills"
    end
  end
  ```

  Test `test/channels/skills_channel_test.rb`:

  ```ruby
  require "test_helper"

  class SkillsChannelTest < ActionCable::Channel::TestCase
    test "subscribes to the 'skills' stream" do
      subscribe
      assert subscription.confirmed?
      assert_has_stream "skills"
    end
  end
  ```

  Run: `bin/rails test test/channels/skills_channel_test.rb -v`
  Expected: PASS.

- [ ] **Step 4: Wire the `<turbo-cable-stream-source>` + partial extraction.**

  Extract one card markup from `app/views/skills/index.html.erb` into `app/views/skills/_skill.html.erb`:

  ```erb
  <article id="<%= dom_id(skill) %>" class="card">
    <h3><%= link_to skill.name, skill %></h3>
    <p class="txt-subtle"><%= skill.category %></p>
    <p><%= skill.description %></p>
  </article>
  ```

  In `app/views/skills/index.html.erb`, add inside the turbo frame:

  ```erb
  <%= turbo_stream_from "skills" %>

  <%= turbo_frame_tag "skill-results" do %>
    <% @skills.each do |skill| %>
      <%= render skill %>
    <% end %>
  <% end %>
  ```

- [ ] **Step 5: System test the live update.**

  Add to `test/system/skills_test.rb`:

  ```ruby
  test "a skill name change appears in /skills without reload" do
    sign_in_as users(:one)
    visit skills_path
    assert_text "Filesystem"

    skills(:filesystem).update!(name: "Filesystem Updated")
    using_wait_time(3) { assert_text "Filesystem Updated" }
  end
  ```

  Run: `bin/rails test:system test/system/skills_test.rb -v`
  Expected: PASS.

- [ ] **Step 6: Commit.**

  ```bash
  git add app/models/skill.rb \
          app/channels/skills_channel.rb \
          app/views/skills/index.html.erb \
          app/views/skills/_skill.html.erb \
          test/channels/skills_channel_test.rb \
          test/models/skill_broadcast_test.rb \
          test/system/skills_test.rb
  git commit -m "Phase 5 Task 5.3: live /skills updates via after_commit broadcast_replace_to"
  ```

---

## Task 5.4 — Drop `accepted_at` / `enabled_at` columns

Phase 3 carry-over (workflows.md:3040). `SkillInstallation#accepted_at` and `SkillEnablement#enabled_at` both always equal `created_at` — the assignments in `Skill::Installable` / `Skill::Enableable` (`app/models/skill/installable.rb:17`, `app/models/skill/enableable.rb:20`) set them to `Time.current` at create time, but nothing else writes them and no callers read them as anything but a synonym for `created_at`. Drop them.

**Files:**
- Create: `db/migrate/<ts>_drop_redundant_timestamps.rb`
- Modify: `app/models/skill/installable.rb`
- Modify: `app/models/skill/enableable.rb`
- Modify: `db/schema.rb` (auto)

- [ ] **Step 1: Migration.**

  ```bash
  bin/rails g migration DropRedundantTimestamps
  ```

  Edit:

  ```ruby
  class DropRedundantTimestamps < ActiveRecord::Migration[8.1]
    def change
      remove_column :skill_installations, :accepted_at, :datetime, null: false
      remove_column :skill_enablements,   :enabled_at,  :datetime, null: false
    end
  end
  ```

  Run: `bin/rails db:migrate db:test:prepare`

- [ ] **Step 2: Remove the dead assignments.**

  In `app/models/skill/installable.rb`, drop `i.accepted_at = Time.current` from the `find_or_create_by!` block.
  In `app/models/skill/enableable.rb`, drop `e.enabled_at = Time.current` from the `find_or_create_by!` block.

- [ ] **Step 3: Run the model + system tests.**

  ```bash
  bin/rails test test/models/skill_installation_test.rb \
                 test/models/skill_enablement_test.rb \
                 test/models/skill/installable_test.rb \
                 test/models/skill/enableable_test.rb \
                 test/system/skills_test.rb
  ```

  Expected: all green. If a test asserts on `accepted_at` / `enabled_at`, switch to `created_at`.

- [ ] **Step 4: Update fixtures if they reference the dropped columns.**

  ```bash
  grep -rn "accepted_at\|enabled_at" test/fixtures/
  ```

  Remove any matches. Re-run the suite above.

- [ ] **Step 5: Commit.**

  ```bash
  git add db/migrate/<ts>_drop_redundant_timestamps.rb \
          db/schema.rb \
          app/models/skill/installable.rb \
          app/models/skill/enableable.rb \
          test/fixtures/
  git commit -m "Phase 5 Task 5.4: drop SkillInstallation#accepted_at + SkillEnablement#enabled_at (collapse to created_at)"
  ```

---

## Task 5.5 — `scheduled_jobs` + `scheduled_job_pauses` migrations + `ScheduledJob` skeleton

`ScheduledJob` is the core entity. Schema fields from workflows.md:134. Pause is a child record (workflows.md:154) per the `chat_session_archives` pattern.

**Files:**
- Create: `db/migrate/<ts>_create_scheduled_jobs.rb`
- Create: `db/migrate/<ts>_create_scheduled_job_pauses.rb`
- Create: `app/models/scheduled_job.rb`
- Create: `app/models/scheduled_job/pause.rb`
- Create: `app/models/scheduled_job/pausable.rb`
- Create: `test/fixtures/scheduled_jobs.yml`
- Create: `test/fixtures/scheduled_job_pauses.yml`
- Create: `test/models/scheduled_job_test.rb`

- [ ] **Step 1: Migrations.**

  ```bash
  bin/rails g migration CreateScheduledJobs
  bin/rails g migration CreateScheduledJobPauses
  ```

  Edit `db/migrate/<ts>_create_scheduled_jobs.rb`:

  ```ruby
  class CreateScheduledJobs < ActiveRecord::Migration[8.1]
    def change
      create_table :scheduled_jobs do |t|
        t.references :user, null: false, foreign_key: true
        t.string  :name,   null: false
        t.string  :cron,   null: false
        t.text    :prompt, null: false
        t.string  :model,  null: false
        t.string  :provider, null: false
        t.json    :skill_slugs, default: [], null: false
        t.datetime :next_run_at
        t.datetime :last_run_at
        t.timestamps
      end
      add_index :scheduled_jobs, :next_run_at
      add_index :scheduled_jobs, %i[user_id name], unique: true
    end
  end
  ```

  Edit `db/migrate/<ts>_create_scheduled_job_pauses.rb`:

  ```ruby
  class CreateScheduledJobPauses < ActiveRecord::Migration[8.1]
    def change
      create_table :scheduled_job_pauses do |t|
        t.references :scheduled_job, null: false, foreign_key: true
        t.references :user, null: false, foreign_key: true
        t.string :reason
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end
      add_index :scheduled_job_pauses, :scheduled_job_id, unique: true, name: "index_scheduled_job_pauses_on_sjid_unique"
    end
  end
  ```

  Run: `bin/rails db:migrate db:test:prepare`

- [ ] **Step 2: Pause model.**

  `app/models/scheduled_job/pause.rb`:

  ```ruby
  class ScheduledJob::Pause < ApplicationRecord
    self.table_name = "scheduled_job_pauses"

    belongs_to :scheduled_job
    belongs_to :user, default: -> { Current.user }
  end
  ```

- [ ] **Step 3: Pausable concern (mirror `Archivable`).**

  `app/models/scheduled_job/pausable.rb`:

  ```ruby
  module ScheduledJob::Pausable
    extend ActiveSupport::Concern

    included do
      has_one :pause_record, class_name: "ScheduledJob::Pause",
                             foreign_key: :scheduled_job_id, dependent: :destroy
      scope :paused, -> { joins(:pause_record) }
      scope :active, -> { where.missing(:pause_record) }
    end

    def paused?
      pause_record.present?
    end

    def active?
      !paused?
    end

    def pause(reason: nil, user: Current.user)
      return if paused?
      transaction do
        create_pause_record!(user: user, reason: reason)
        track_event :paused, creator: user, reason: reason
      end
    end

    def resume(user: Current.user)
      return unless paused?
      transaction do
        pause_record.destroy!
        track_event :resumed, creator: user
      end
    end
  end
  ```

- [ ] **Step 4: ScheduledJob skeleton + fixtures.**

  `app/models/scheduled_job.rb`:

  ```ruby
  class ScheduledJob < ApplicationRecord
    include Eventable
    include ScheduledJob::Pausable

    belongs_to :user, default: -> { Current.user }
    has_many :runs, class_name: "JobRun", dependent: :destroy

    validates :name, :cron, :prompt, :model, :provider, presence: true
    validates :name, uniqueness: { scope: :user_id }

    before_validation :default_skill_slugs

    private

    def default_skill_slugs
      self.skill_slugs ||= []
    end
  end
  ```

  `test/fixtures/scheduled_jobs.yml`:

  ```yaml
  daily_digest:
    user: one
    name: "Daily digest"
    cron: "0 9 * * *"
    prompt: "Summarize yesterday's commits"
    model: claude-haiku-4-5
    provider: anthropic
    skill_slugs: <%= [].to_json %>
    next_run_at: <%= 1.hour.from_now.iso8601 %>

  hourly_lint:
    user: one
    name: "Hourly lint"
    cron: "0 * * * *"
    prompt: "Check rubocop"
    model: claude-haiku-4-5
    provider: anthropic
    skill_slugs: <%= [].to_json %>
    next_run_at: <%= 5.minutes.ago.iso8601 %>
  ```

  `test/fixtures/scheduled_job_pauses.yml`:

  ```yaml
  # empty by default; tests create rows inline
  ```

- [ ] **Step 5: Failing then passing tests.**

  `test/models/scheduled_job_test.rb`:

  ```ruby
  require "test_helper"

  class ScheduledJobTest < ActiveSupport::TestCase
    test "name is unique per user" do
      original = scheduled_jobs(:daily_digest)
      dup      = ScheduledJob.new(user: original.user, name: original.name, cron: "* * * * *",
                                  prompt: "x", model: "claude-haiku-4-5", provider: "anthropic")
      assert_not dup.valid?
      assert_includes dup.errors[:name], "has already been taken"
    end

    test "Pausable: pause + resume + scopes" do
      job = scheduled_jobs(:daily_digest)
      assert job.active?
      job.pause(reason: "manual")
      assert job.reload.paused?
      assert_includes ScheduledJob.paused, job
      assert_not_includes ScheduledJob.active, job

      job.resume
      assert job.reload.active?
    end

    test "pause writes an Event with reason particulars" do
      job = scheduled_jobs(:daily_digest)
      assert_difference -> { job.events.where(action: "scheduled_job_paused").count }, +1 do
        job.pause(reason: "rate limit")
      end
      ev = job.events.where(action: "scheduled_job_paused").last
      assert_equal "rate limit", ev.particulars["reason"]
    end
  end
  ```

  Run: `bin/rails test test/models/scheduled_job_test.rb -v`
  Expected: PASS.

- [ ] **Step 6: Commit.**

  ```bash
  git add db/migrate/<ts>_create_scheduled_jobs.rb \
          db/migrate/<ts>_create_scheduled_job_pauses.rb \
          db/schema.rb \
          app/models/scheduled_job.rb \
          app/models/scheduled_job/pause.rb \
          app/models/scheduled_job/pausable.rb \
          test/fixtures/scheduled_jobs.yml \
          test/fixtures/scheduled_job_pauses.yml \
          test/models/scheduled_job_test.rb
  git commit -m "Phase 5 Task 5.5: scheduled_jobs + scheduled_job_pauses tables + ScheduledJob + Pausable concern"
  ```

---

## Task 5.6 — `job_runs` migration + `JobRun` model

Per workflows.md:135. One row per execution. `output` is bounded — overflow goes to disk via a workspace path (Task 5.10 implements the cap).

**Files:**
- Create: `db/migrate/<ts>_create_job_runs.rb`
- Create: `app/models/job_run.rb`
- Create: `test/fixtures/job_runs.yml`
- Create: `test/models/job_run_test.rb`

- [ ] **Step 1: Migration.**

  ```bash
  bin/rails g migration CreateJobRuns
  ```

  ```ruby
  class CreateJobRuns < ActiveRecord::Migration[8.1]
    def change
      create_table :job_runs do |t|
        t.references :scheduled_job, null: false, foreign_key: true
        t.references :chat_session, foreign_key: true   # nullable: pre-creation rows are :pending
        t.datetime :started_at
        t.datetime :finished_at
        t.integer :status, default: 0, null: false
        t.text :output
        t.integer :exit_code
        t.integer :prompt_tokens
        t.integer :completion_tokens
        t.integer :cache_read_tokens
        t.integer :cache_creation_tokens
        t.decimal :cost_usd, precision: 12, scale: 6
        t.text :error_message
        t.timestamps
      end
      add_index :job_runs, %i[scheduled_job_id created_at]
      add_index :job_runs, :status
    end
  end
  ```

  Run: `bin/rails db:migrate db:test:prepare`

- [ ] **Step 2: JobRun model.**

  `app/models/job_run.rb`:

  ```ruby
  class JobRun < ApplicationRecord
    include Eventable

    belongs_to :scheduled_job
    belongs_to :chat_session, optional: true

    enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4 }

    scope :recent,   -> { order(created_at: :desc) }
    scope :finished, -> { where(status: %i[succeeded failed cancelled]) }

    def duration_seconds
      return nil unless started_at && finished_at
      (finished_at - started_at).round(2)
    end
  end
  ```

- [ ] **Step 3: Fixtures.**

  `test/fixtures/job_runs.yml`:

  ```yaml
  succeeded_one:
    scheduled_job: daily_digest
    chat_session: one
    started_at: <%= 1.hour.ago.iso8601 %>
    finished_at: <%= (1.hour.ago + 4.seconds).iso8601 %>
    status: 2
    output: "Done."
    prompt_tokens: 200
    completion_tokens: 80
    cost_usd: "0.001500"
  ```

- [ ] **Step 4: Tests.**

  `test/models/job_run_test.rb`:

  ```ruby
  require "test_helper"

  class JobRunTest < ActiveSupport::TestCase
    test "enum statuses round-trip" do
      run = job_runs(:succeeded_one)
      assert run.succeeded?
      run.update!(status: :failed)
      assert run.reload.failed?
    end

    test "duration_seconds nil until both timestamps set" do
      run = scheduled_jobs(:daily_digest).runs.create!(status: :pending)
      assert_nil run.duration_seconds
      run.update!(started_at: 1.second.ago, finished_at: Time.current)
      assert_in_delta 1, run.duration_seconds, 0.5
    end
  end
  ```

  Run: `bin/rails test test/models/job_run_test.rb -v`
  Expected: PASS.

- [ ] **Step 5: Commit.**

  ```bash
  git add db/migrate/<ts>_create_job_runs.rb \
          db/schema.rb \
          app/models/job_run.rb \
          test/fixtures/job_runs.yml \
          test/models/job_run_test.rb
  git commit -m "Phase 5 Task 5.6: job_runs table + JobRun model + status enum + Eventable"
  ```

---

## Task 5.7 — `ScheduledJob::Cron` value object (fugit wrapper)

Parses cron with `fugit`, exposes `next_run_at(from:)`, rejects unbounded schedules. A 5-line wrapper that we can test in isolation — `SchedulerTickJob` then doesn't reach into `Fugit` directly.

**Files:**
- Create: `app/models/scheduled_job/cron.rb`
- Create: `test/models/scheduled_job/cron_test.rb`

- [ ] **Step 1: Failing test.**

  `test/models/scheduled_job/cron_test.rb`:

  ```ruby
  require "test_helper"

  class ScheduledJob::CronTest < ActiveSupport::TestCase
    test "parses a standard cron string" do
      cron = ScheduledJob::Cron.new("0 9 * * *")
      from = Time.utc(2026, 5, 17, 8, 0, 0)
      assert_equal Time.utc(2026, 5, 17, 9, 0, 0), cron.next_run_at(from: from)
    end

    test "raises Invalid on garbage" do
      assert_raises(ScheduledJob::Cron::Invalid) { ScheduledJob::Cron.new("definitely not cron") }
    end

    test "rejects sub-minute schedules (resolution cap matches SchedulerTickJob's every-1-minute cadence)" do
      assert_raises(ScheduledJob::Cron::TooFrequent) { ScheduledJob::Cron.new("* * * * * *") }
    end
  end
  ```

  Run: `bin/rails test test/models/scheduled_job/cron_test.rb -v`
  Expected: FAIL — `NameError: uninitialized constant ScheduledJob::Cron`.

- [ ] **Step 2: Implementation.**

  `app/models/scheduled_job/cron.rb`:

  ```ruby
  class ScheduledJob::Cron
    class Invalid       < StandardError; end
    class TooFrequent   < StandardError; end

    MIN_INTERVAL_SECONDS = 60   # SchedulerTickJob fires every 60s; finer is meaningless

    def initialize(expression)
      @expression = expression.to_s
      @cron       = Fugit::Cron.parse(@expression)
      raise Invalid, "#{@expression.inspect} is not a valid cron expression" unless @cron
      raise TooFrequent, "sub-minute cron #{@expression.inspect} rejected (SchedulerTickJob fires every 60s)" if too_frequent?
    end

    def next_run_at(from: Time.current)
      Time.at(@cron.next_time(from).to_i).utc
    end

    private

    def too_frequent?
      sample = @cron.next_time(Time.at(0)).to_i
      delta  = @cron.next_time(Time.at(sample)).to_i - sample
      delta < MIN_INTERVAL_SECONDS
    end
  end
  ```

  Run: `bin/rails test test/models/scheduled_job/cron_test.rb -v`
  Expected: PASS.

- [ ] **Step 3: Wire validation into ScheduledJob.**

  Add to `app/models/scheduled_job.rb`:

  ```ruby
  validate :cron_expression_parses

  def cron_parser
    ScheduledJob::Cron.new(cron) if cron.present?
  rescue ScheduledJob::Cron::Invalid, ScheduledJob::Cron::TooFrequent
    nil
  end

  def compute_next_run_at(from: Time.current)
    cron_parser&.next_run_at(from: from)
  end

  private

  def cron_expression_parses
    return if cron.blank?
    ScheduledJob::Cron.new(cron)
  rescue ScheduledJob::Cron::Invalid => e
    errors.add(:cron, e.message)
  rescue ScheduledJob::Cron::TooFrequent => e
    errors.add(:cron, e.message)
  end
  ```

  Add to `test/models/scheduled_job_test.rb`:

  ```ruby
  test "validates cron syntax" do
    sj = scheduled_jobs(:daily_digest)
    sj.cron = "lol"
    assert_not sj.valid?
    assert_match(/not a valid cron/, sj.errors[:cron].first)
  end

  test "compute_next_run_at returns a fugit-parsed time" do
    sj = scheduled_jobs(:daily_digest)
    sj.cron = "0 9 * * *"
    assert sj.compute_next_run_at(from: Time.utc(2026, 5, 17, 8)).hour == 9
  end
  ```

  Run: `bin/rails test test/models/scheduled_job_test.rb test/models/scheduled_job/cron_test.rb -v`
  Expected: PASS.

- [ ] **Step 4: Commit.**

  ```bash
  git add app/models/scheduled_job/cron.rb \
          app/models/scheduled_job.rb \
          test/models/scheduled_job/cron_test.rb \
          test/models/scheduled_job_test.rb
  git commit -m "Phase 5 Task 5.7: ScheduledJob::Cron value object (fugit wrapper) + validation"
  ```

---

## Task 5.8 — `ScheduledJob.run_all_due` + `SchedulerTickJob`

The 3-line wrapper job that the recurring scheduler fires every minute. Class method on `ScheduledJob` does the row-selection work so the job stays 1 line.

**Files:**
- Modify: `app/models/scheduled_job.rb`
- Create: `app/jobs/scheduler_tick_job.rb`
- Modify: `config/recurring.yml`
- Create: `test/jobs/scheduler_tick_job_test.rb`
- Create: `app/jobs/scheduled_job/runner_job.rb`

- [ ] **Step 1: Failing test.**

  `test/jobs/scheduler_tick_job_test.rb`:

  ```ruby
  require "test_helper"

  class SchedulerTickJobTest < ActiveJob::TestCase
    test "enqueues RunnerJob for each due, active job" do
      due       = scheduled_jobs(:hourly_lint)   # next_run_at: 5 minutes ago
      not_due   = scheduled_jobs(:daily_digest)  # next_run_at: 1 hour from now
      paused    = scheduled_jobs(:hourly_lint)
      paused.pause(reason: "test")

      assert_no_enqueued_jobs do
        SchedulerTickJob.perform_now
      end

      paused.resume
      assert_enqueued_with(job: ScheduledJob::RunnerJob, args: [ due ]) do
        SchedulerTickJob.perform_now
      end
      assert_no_enqueued_jobs only: ScheduledJob::RunnerJob, args: [ not_due ]
    end
  end
  ```

  Run: `bin/rails test test/jobs/scheduler_tick_job_test.rb -v`
  Expected: FAIL — `NameError: uninitialized constant SchedulerTickJob`.

- [ ] **Step 2: `ScheduledJob.run_all_due` class method.**

  Add to `app/models/scheduled_job.rb`:

  ```ruby
  scope :due, ->(now = Time.current) { where(next_run_at: ..now) }

  class << self
    def run_all_due(now: Time.current)
      active.due(now).find_each do |job|
        ScheduledJob::RunnerJob.perform_later(job)
      end
    end
  end
  ```

- [ ] **Step 3: Implement `SchedulerTickJob` + `ScheduledJob::RunnerJob`.**

  `app/jobs/scheduler_tick_job.rb`:

  ```ruby
  class SchedulerTickJob < ApplicationJob
    queue_as :default

    def perform
      ScheduledJob.run_all_due
    end
  end
  ```

  `app/jobs/scheduled_job/runner_job.rb`:

  ```ruby
  class ScheduledJob::RunnerJob < ApplicationJob
    queue_as :default

    def perform(scheduled_job)
      scheduled_job.run!
    end
  end
  ```

  (`#run!` is implemented in Task 5.10; a passing wrapper is enough here — `RunnerJob` stays a 3-line wrapper.)

  Stub `ScheduledJob#run!` for now in `app/models/scheduled_job.rb`:

  ```ruby
  def run!
    raise NotImplementedError
  end
  ```

  Run: `bin/rails test test/jobs/scheduler_tick_job_test.rb -v`
  Expected: PASS.

- [ ] **Step 4: Register recurring entry.**

  Add to `config/recurring.yml` under `production:`:

  ```yaml
  scheduler_tick:
    class: SchedulerTickJob
    schedule: every 1 minute
  ```

- [ ] **Step 5: Commit.**

  ```bash
  git add app/models/scheduled_job.rb \
          app/jobs/scheduler_tick_job.rb \
          app/jobs/scheduled_job/runner_job.rb \
          config/recurring.yml \
          test/jobs/scheduler_tick_job_test.rb
  git commit -m "Phase 5 Task 5.8: SchedulerTickJob + ScheduledJob.run_all_due + RunnerJob wrapper + recurring entry"
  ```

---

## Task 5.9 — `ScheduledJob#run!` end-to-end

The meat of Phase 5. `#run!` spins up a fresh `ChatSession`, posts a user message with the prompt, drives `Message#advance!` synchronously (no `_later` — we're already inside `RunnerJob`), captures cost/tokens into a `JobRun` row, and advances `next_run_at` + `last_run_at`. Bounded output size — anything past `MAX_JOB_RUN_OUTPUT_BYTES` (default 256 KiB) is truncated with an ellipsis + overflow note (Phase 7 surfaces a "download full output" button; for Phase 5 the truncation is the cap).

**Files:**
- Modify: `app/models/scheduled_job.rb`
- Create: `app/models/scheduled_job/runnable.rb`
- Create: `test/models/scheduled_job/runnable_test.rb`

- [ ] **Step 1: Failing test.**

  `test/models/scheduled_job/runnable_test.rb`:

  ```ruby
  require "test_helper"

  class ScheduledJob::RunnableTest < ActiveSupport::TestCase
    setup do
      @sj = scheduled_jobs(:daily_digest)
      # Stub Llm::Client.for so #advance! returns deterministically without HTTP.
      @adapter = Struct.new(:provider).new("anthropic")
      def @adapter.stream(messages:, tools:, model:, system: nil)
        yield(type: :message_start, message_id: "msg_x", model: model)
        yield(type: :content_block_start, index: 0, block: { type: "text", text: "" })
        yield(type: :text_delta, index: 0, text: "Hello from scheduled job")
        yield(type: :content_block_stop, index: 0)
        yield(type: :message_stop, finish_reason: "end_turn")
        { prompt_tokens: 12, completion_tokens: 7, cache_read_tokens: 0, cache_creation_tokens: 0,
          finish_reason: "end_turn" }
      end
      Llm::Client.singleton_class.define_method(:for) { |provider:| TestRunnableAdapter.instance }
    end

    teardown do
      Llm::Client.singleton_class.remove_method(:for) rescue nil
      load Rails.root.join("app/services/llm/client.rb")
    end

    test "run! produces a succeeded JobRun with cost + output captured" do
      run = nil
      assert_difference -> { JobRun.count }, +1 do
        run = @sj.run!
      end
      assert run.succeeded?
      assert_match(/Hello from scheduled job/, run.output)
      assert run.cost_usd.positive?
      assert_equal 12, run.prompt_tokens
      assert_equal 7,  run.completion_tokens
      assert_not_nil run.chat_session
    end

    test "run! advances next_run_at + last_run_at" do
      before = @sj.next_run_at
      @sj.run!
      @sj.reload
      assert_not_equal before, @sj.next_run_at
      assert_not_nil @sj.last_run_at
    end

    test "adapter raises → JobRun is :failed with error_message" do
      Llm::Client.singleton_class.define_method(:for) { |provider:| raise "boom" }
      run = @sj.run!
      assert run.failed?
      assert_equal "boom", run.error_message
    end
  end
  ```

  (Use the existing test pattern — `Llm::Client.for` is monkey-stubbed during the test only; the teardown re-loads the original. The `TestRunnableAdapter` is defined at the top of the test file as a Module/Singleton if needed — adjust to match the codebase's existing stubbing helpers.)

  Run: `bin/rails test test/models/scheduled_job/runnable_test.rb -v`
  Expected: FAIL — `ScheduledJob#run!` raises `NotImplementedError`.

- [ ] **Step 2: Extract `Runnable` concern + implement.**

  `app/models/scheduled_job/runnable.rb`:

  ```ruby
  module ScheduledJob::Runnable
    extend ActiveSupport::Concern

    MAX_OUTPUT_BYTES = 256 * 1024  # 256 KiB cap on the JobRun.output column
    SUMMARY_BLOCK_LIMIT = 8         # keep the first N text blocks in the rollup

    def run!(now: Time.current)
      run = runs.create!(status: :running, started_at: now)
      chat = create_run_chat_session(run)
      run.update!(chat_session: chat)
      track_event :run_started, job_run_id: run.id, chat_session_id: chat.id

      drive_assistant(chat, run)
      capture_success(run, chat)
      advance_schedule(now)
      run
    rescue StandardError => e
      capture_failure(run, e) if run
      advance_schedule(now)
      run
    end

    private

    def drive_assistant(chat, _run)
      chat.messages.create!(
        role: :user, status: :completed,
        content_blocks: [ { type: "text", text: prompt } ],
        model: model, provider: provider
      )
      assistant = chat.messages.create!(
        role: :assistant, status: :pending,
        content_blocks: [], model: model, provider: provider
      )
      assistant.advance!   # synchronous — already on a worker via RunnerJob
    end

    def capture_success(run, chat)
      assistant = chat.messages.where(role: :assistant).order(:created_at).last
      text = extract_text_output(assistant)
      run.update!(
        status:                :succeeded,
        finished_at:           Time.current,
        output:                truncate_output(text),
        prompt_tokens:         assistant.prompt_tokens,
        completion_tokens:     assistant.completion_tokens,
        cache_read_tokens:     assistant.cache_read_tokens,
        cache_creation_tokens: assistant.cache_creation_tokens,
        cost_usd:              assistant.cost_usd || assistant.compute_cost
      )
      track_event :run_succeeded, job_run_id: run.id, cost_usd: run.cost_usd.to_s, tokens: run.prompt_tokens.to_i + run.completion_tokens.to_i
    end

    def capture_failure(run, error)
      run.update!(status: :failed, finished_at: Time.current, error_message: error.message)
      track_event :run_failed, job_run_id: run.id, error_class: error.class.name, error_message: error.message
    end

    def extract_text_output(assistant)
      Array(assistant.content_blocks).filter_map { |b| b["text"] if b.is_a?(Hash) && b["type"] == "text" }.join("\n\n")
    end

    def truncate_output(text)
      return text if text.bytesize <= MAX_OUTPUT_BYTES
      text.byteslice(0, MAX_OUTPUT_BYTES).to_s.scrub + "\n…[truncated #{text.bytesize - MAX_OUTPUT_BYTES} bytes]"
    end

    def create_run_chat_session(run)
      ChatSession.create!(
        user:     user,
        title:    "Job: #{name} (#{run.created_at.utc.iso8601})",
        model:    model,
        provider: provider,
        last_active_at: Time.current
      )
    end

    def advance_schedule(now)
      update!(last_run_at: now, next_run_at: compute_next_run_at(from: now))
    end
  end
  ```

  In `app/models/scheduled_job.rb`, include the concern:

  ```ruby
  include ScheduledJob::Pausable
  include ScheduledJob::Runnable
  ```

  Remove the stub `def run!; raise NotImplementedError; end`.

  Run: `bin/rails test test/models/scheduled_job/runnable_test.rb -v`
  Expected: PASS.

- [ ] **Step 3: ScheduledJob#run! sets next_run_at on creation too.**

  Add to `app/models/scheduled_job.rb`:

  ```ruby
  before_validation :default_next_run_at, on: :create

  private

  def default_next_run_at
    return if next_run_at.present?
    self.next_run_at = compute_next_run_at
  end
  ```

  Test:

  ```ruby
  test "on create, next_run_at defaults from cron" do
    sj = users(:one).scheduled_jobs.create!(name: "Test", cron: "0 0 * * *",
                                            prompt: "x", model: "claude-haiku-4-5", provider: "anthropic")
    assert_not_nil sj.next_run_at
    assert sj.next_run_at > Time.current
  end
  ```

  Run: `bin/rails test test/models/scheduled_job_test.rb -v`
  Expected: PASS.

- [ ] **Step 4: Wire `user.scheduled_jobs` association.**

  In `app/models/user.rb`:

  ```ruby
  has_many :scheduled_jobs, dependent: :destroy
  ```

- [ ] **Step 5: Commit.**

  ```bash
  git add app/models/scheduled_job/runnable.rb \
          app/models/scheduled_job.rb \
          app/models/user.rb \
          test/models/scheduled_job/runnable_test.rb \
          test/models/scheduled_job_test.rb
  git commit -m "Phase 5 Task 5.9: ScheduledJob#run! spins ChatSession + drives advance! + captures JobRun (Runnable concern)"
  ```

---

## Task 5.10 — `ScheduledJobsController` CRUD + scope concern + routes

Per workflows § 9 (line 598): `resources :scheduled_jobs, path: "jobs"`. Controller mirrors `ChatSessionsController` — set-then-act, scope through `Current.user.scheduled_jobs`.

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/scheduled_jobs_controller.rb`
- Create: `app/controllers/concerns/scheduled_job_scoped.rb`
- Create: `test/controllers/scheduled_jobs_controller_test.rb`

- [ ] **Step 1: Routes.**

  Add to `config/routes.rb` before `resources :mcp_servers`:

  ```ruby
  resources :scheduled_jobs, path: "jobs" do
    scope module: :scheduled_jobs do
      resource  :pause, only: %i[create destroy]
      resources :runs,  only: %i[index show create]
    end
  end
  ```

- [ ] **Step 2: ScheduledJobScoped concern.**

  `app/controllers/concerns/scheduled_job_scoped.rb`:

  ```ruby
  module ScheduledJobScoped
    extend ActiveSupport::Concern

    included do
      before_action :set_scheduled_job
    end

    private

    def set_scheduled_job
      @scheduled_job = Current.user.scheduled_jobs.find(params[:scheduled_job_id] || params[:id])
    end
  end
  ```

- [ ] **Step 3: Failing controller tests (cross-tenancy + CRUD).**

  `test/controllers/scheduled_jobs_controller_test.rb`:

  ```ruby
  require "test_helper"

  class ScheduledJobsControllerTest < ActionDispatch::IntegrationTest
    include ControllerSignInHelpers

    test "GET /jobs as authed user lists own jobs" do
      sign_in_as users(:one)
      get scheduled_jobs_path
      assert_response :success
      assert_select "h1", "Jobs"
    end

    test "POST /jobs creates and redirects" do
      sign_in_as users(:one)
      assert_difference -> { ScheduledJob.count }, +1 do
        post scheduled_jobs_path, params: {
          scheduled_job: { name: "Nightly", cron: "0 3 * * *", prompt: "x",
                           model: "claude-haiku-4-5", provider: "anthropic" }
        }
      end
      assert_redirected_to scheduled_job_path(ScheduledJob.last)
    end

    test "GET /jobs/:id of another user returns 404 (cross-tenancy)" do
      sign_in_as users(:member)
      assert_raises(ActiveRecord::RecordNotFound) do
        get scheduled_job_path(scheduled_jobs(:daily_digest))
      end
    end

    test "DELETE /jobs/:id of own job destroys it" do
      sign_in_as users(:one)
      sj = scheduled_jobs(:daily_digest)
      assert_difference -> { ScheduledJob.count }, -1 do
        delete scheduled_job_path(sj)
      end
      assert_redirected_to scheduled_jobs_path
    end
  end
  ```

  Run: `bin/rails test test/controllers/scheduled_jobs_controller_test.rb -v`
  Expected: FAIL — no controller / no views.

- [ ] **Step 4: Controller + minimal views.**

  `app/controllers/scheduled_jobs_controller.rb`:

  ```ruby
  class ScheduledJobsController < ApplicationController
    before_action :set_scheduled_job, only: %i[show edit update destroy]

    def index
      @scheduled_jobs = Current.user.scheduled_jobs.order(:name)
    end

    def show
      @recent_runs = @scheduled_job.runs.recent.limit(20)
    end

    def new
      @scheduled_job = Current.user.scheduled_jobs.new(model: default_model, provider: "anthropic")
    end

    def create
      @scheduled_job = Current.user.scheduled_jobs.new(scheduled_job_params)
      if @scheduled_job.save
        redirect_to @scheduled_job, notice: "Job scheduled."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @scheduled_job.update(scheduled_job_params)
        redirect_to @scheduled_job, notice: "Job updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @scheduled_job.destroy
      redirect_to scheduled_jobs_path, notice: "Job removed."
    end

    private

    def set_scheduled_job
      @scheduled_job = Current.user.scheduled_jobs.find(params[:id])
    end

    def scheduled_job_params
      params.expect(scheduled_job: %i[name cron prompt model provider skill_slugs])
    end

    def default_model
      ENV.fetch("MOP_DEFAULT_MODEL") { Llm::Pricing.models_for("anthropic").first }
    end
  end
  ```

  Run: `bin/rails test test/controllers/scheduled_jobs_controller_test.rb -v`
  Expected: most PASS, the index/new/show test may still fail without views.

- [ ] **Step 5: Minimal views.**

  `app/views/scheduled_jobs/index.html.erb`:

  ```erb
  <% content_for :title, "Jobs" %>

  <section class="pad max-width">
    <h1>Jobs</h1>
    <%= link_to "New job", new_scheduled_job_path, class: "btn" %>

    <%= turbo_frame_tag "scheduled-jobs-list" do %>
      <ul class="card-list">
        <% @scheduled_jobs.each do |job| %>
          <%= render "scheduled_job_row", job: job %>
        <% end %>
      </ul>
    <% end %>
  </section>
  ```

  `app/views/scheduled_jobs/_scheduled_job_row.html.erb`:

  ```erb
  <li id="<%= dom_id(job) %>" class="card">
    <%= link_to job.name, job %>
    <span class="txt-subtle"><%= job.cron %></span>
    <span class="txt-subtle">next: <%= job.next_run_at&.iso8601 %></span>
    <% if job.paused? %><span class="badge">paused</span><% end %>
  </li>
  ```

  `app/views/scheduled_jobs/show.html.erb`:

  ```erb
  <% content_for :title, @scheduled_job.name %>

  <section class="pad max-width">
    <h1><%= @scheduled_job.name %></h1>
    <p class="txt-subtle"><code><%= @scheduled_job.cron %></code> — next: <%= @scheduled_job.next_run_at&.iso8601 %></p>

    <%= link_to "Edit", edit_scheduled_job_path(@scheduled_job), class: "btn" %>
    <% if @scheduled_job.paused? %>
      <%= button_to "Resume", scheduled_job_pause_path(@scheduled_job), method: :delete, class: "btn" %>
    <% else %>
      <%= button_to "Pause", scheduled_job_pause_path(@scheduled_job), method: :post, class: "btn" %>
    <% end %>
    <%= button_to "Run now", scheduled_job_runs_path(@scheduled_job), method: :post, class: "btn" %>
    <%= button_to "Delete", @scheduled_job, method: :delete, class: "btn btn-danger", data: { turbo_confirm: "Sure?" } %>

    <h2>Recent runs</h2>
    <%= turbo_frame_tag dom_id(@scheduled_job, :runs) do %>
      <ul class="card-list">
        <% @recent_runs.each do |run| %>
          <%= render "scheduled_jobs/runs/run", run: run %>
        <% end %>
      </ul>
    <% end %>
  </section>
  ```

  `app/views/scheduled_jobs/new.html.erb` + `edit.html.erb` + `_form.html.erb` (minimal form for `name, cron, prompt, model, provider`).

  Run: `bin/rails test test/controllers/scheduled_jobs_controller_test.rb -v`
  Expected: PASS.

- [ ] **Step 6: Commit.**

  ```bash
  git add config/routes.rb \
          app/controllers/scheduled_jobs_controller.rb \
          app/controllers/concerns/scheduled_job_scoped.rb \
          app/views/scheduled_jobs/ \
          test/controllers/scheduled_jobs_controller_test.rb
  git commit -m "Phase 5 Task 5.10: ScheduledJobsController CRUD + ScheduledJobScoped + routes + minimal views"
  ```

---

## Task 5.11 — `ScheduledJobs::PausesController` (pause / resume)

3-line controller mirroring `ChatSessions::ArchivesController`.

**Files:**
- Create: `app/controllers/scheduled_jobs/pauses_controller.rb`
- Create: `test/controllers/scheduled_jobs/pauses_controller_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class ScheduledJobs::PausesControllerTest < ActionDispatch::IntegrationTest
    include ControllerSignInHelpers

    test "POST creates pause" do
      sign_in_as users(:one)
      sj = scheduled_jobs(:daily_digest)
      assert_changes -> { sj.reload.paused? }, from: false, to: true do
        post scheduled_job_pause_path(sj)
      end
      assert_redirected_to scheduled_job_path(sj)
    end

    test "DELETE resumes" do
      sign_in_as users(:one)
      sj = scheduled_jobs(:daily_digest)
      sj.pause
      assert_changes -> { sj.reload.paused? }, from: true, to: false do
        delete scheduled_job_pause_path(sj)
      end
    end

    test "cross-tenancy: cannot pause another user's job" do
      sign_in_as users(:member)
      assert_raises(ActiveRecord::RecordNotFound) do
        post scheduled_job_pause_path(scheduled_jobs(:daily_digest))
      end
    end
  end
  ```

  Run: `bin/rails test test/controllers/scheduled_jobs/pauses_controller_test.rb -v`
  Expected: FAIL.

- [ ] **Step 2: Controller.**

  `app/controllers/scheduled_jobs/pauses_controller.rb`:

  ```ruby
  class ScheduledJobs::PausesController < ApplicationController
    include ScheduledJobScoped

    def create
      @scheduled_job.pause(reason: params[:reason])
      redirect_to @scheduled_job, notice: "Paused."
    end

    def destroy
      @scheduled_job.resume
      redirect_to @scheduled_job, notice: "Resumed."
    end
  end
  ```

  Run: `bin/rails test test/controllers/scheduled_jobs/pauses_controller_test.rb -v`
  Expected: PASS.

- [ ] **Step 3: Commit.**

  ```bash
  git add app/controllers/scheduled_jobs/pauses_controller.rb \
          test/controllers/scheduled_jobs/pauses_controller_test.rb
  git commit -m "Phase 5 Task 5.11: ScheduledJobs::PausesController (pause/resume via resource :pause)"
  ```

---

## Task 5.12 — `ScheduledJobs::RunsController` + manual-run flow + views

`index` and `show` are read-only views; `create` enqueues a `RunnerJob` immediately (manual "Run now" button).

**Files:**
- Create: `app/controllers/scheduled_jobs/runs_controller.rb`
- Create: `app/views/scheduled_jobs/runs/index.html.erb`
- Create: `app/views/scheduled_jobs/runs/show.html.erb`
- Create: `app/views/scheduled_jobs/runs/_run.html.erb`
- Create: `test/controllers/scheduled_jobs/runs_controller_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class ScheduledJobs::RunsControllerTest < ActionDispatch::IntegrationTest
    include ControllerSignInHelpers

    test "GET index lists runs" do
      sign_in_as users(:one)
      get scheduled_job_runs_path(scheduled_jobs(:daily_digest))
      assert_response :success
    end

    test "POST create enqueues RunnerJob" do
      sign_in_as users(:one)
      sj = scheduled_jobs(:daily_digest)
      assert_enqueued_with(job: ScheduledJob::RunnerJob, args: [ sj ]) do
        post scheduled_job_runs_path(sj)
      end
      assert_redirected_to scheduled_job_path(sj)
    end

    test "GET show of own run" do
      sign_in_as users(:one)
      get scheduled_job_run_path(scheduled_jobs(:daily_digest), job_runs(:succeeded_one))
      assert_response :success
    end

    test "cross-tenancy: 404 on other user's run" do
      sign_in_as users(:member)
      assert_raises(ActiveRecord::RecordNotFound) do
        get scheduled_job_runs_path(scheduled_jobs(:daily_digest))
      end
    end
  end
  ```

- [ ] **Step 2: Controller.**

  ```ruby
  class ScheduledJobs::RunsController < ApplicationController
    include ScheduledJobScoped
    before_action :set_run, only: :show

    def index
      @runs = @scheduled_job.runs.recent.limit(50)
    end

    def show; end

    def create
      ScheduledJob::RunnerJob.perform_later(@scheduled_job)
      redirect_to @scheduled_job, notice: "Run queued."
    end

    private

    def set_run
      @run = @scheduled_job.runs.find(params[:id])
    end
  end
  ```

- [ ] **Step 3: Views.**

  `_run.html.erb`:

  ```erb
  <li id="<%= dom_id(run) %>" class="card">
    <%= link_to run.created_at.iso8601, scheduled_job_run_path(run.scheduled_job, run) %>
    <span class="badge badge-<%= run.status %>"><%= run.status %></span>
    <span class="txt-subtle"><%= run.duration_seconds %>s</span>
    <span class="txt-subtle">$<%= run.cost_usd %></span>
  </li>
  ```

  `show.html.erb`:

  ```erb
  <% content_for :title, "Run – #{@run.scheduled_job.name}" %>
  <section class="pad max-width">
    <h1>Run <%= @run.id %></h1>
    <p>Status: <span class="badge badge-<%= @run.status %>"><%= @run.status %></span></p>
    <p>Duration: <%= @run.duration_seconds %>s</p>
    <p>Cost: $<%= @run.cost_usd %> (<%= @run.prompt_tokens %> + <%= @run.completion_tokens %> tokens)</p>

    <h2>Output</h2>
    <pre><%= @run.output %></pre>

    <% if @run.failed? %>
      <h2>Error</h2>
      <pre><%= @run.error_message %></pre>
    <% end %>

    <% if @run.chat_session %>
      <%= link_to "Open underlying chat", @run.chat_session %>
    <% end %>
  </section>
  ```

  Run: `bin/rails test test/controllers/scheduled_jobs/runs_controller_test.rb -v`
  Expected: PASS.

- [ ] **Step 4: Commit.**

  ```bash
  git add app/controllers/scheduled_jobs/runs_controller.rb \
          app/views/scheduled_jobs/runs/ \
          test/controllers/scheduled_jobs/runs_controller_test.rb
  git commit -m "Phase 5 Task 5.12: ScheduledJobs::RunsController + runs views + manual run-now"
  ```

---

## Task 5.13 — `JobsChannel` + live run-status broadcast

`stream_for scheduled_job` — when a `JobRun` flips status, the show page updates. Mirror the Task 5.3 pattern.

**Files:**
- Create: `app/channels/jobs_channel.rb`
- Modify: `app/models/job_run.rb`
- Modify: `app/views/scheduled_jobs/show.html.erb` + run partial
- Create: `test/channels/jobs_channel_test.rb`
- Create: `test/models/job_run_broadcast_test.rb`

- [ ] **Step 1: Failing test.**

  ```ruby
  require "test_helper"

  class JobRunBroadcastTest < ActionCable::Channel::TestCase
    test "JobRun status change broadcasts to its ScheduledJob" do
      run = job_runs(:succeeded_one)
      sj  = run.scheduled_job
      stream = "jobs_channel:#{sj.to_gid_param}"
      assert_broadcasts(stream, 1) do
        run.update!(status: :running)
      end
    end
  end
  ```

  Run: `bin/rails test test/models/job_run_broadcast_test.rb -v`
  Expected: FAIL.

- [ ] **Step 2: Add `broadcasts_to :scheduled_job` to JobRun.**

  In `app/models/job_run.rb`:

  ```ruby
  after_commit -> {
    broadcast_replace_to scheduled_job, target: ActionView::RecordIdentifier.dom_id(self),
                         partial: "scheduled_jobs/runs/run", locals: { run: self }
  }, on: %i[create update]
  ```

  `app/channels/jobs_channel.rb`:

  ```ruby
  class JobsChannel < ApplicationCable::Channel
    def subscribed
      scheduled_job = current_user.scheduled_jobs.find(params[:scheduled_job_id])
      stream_for scheduled_job
    end
  end
  ```

- [ ] **Step 3: Wire the view.**

  In `app/views/scheduled_jobs/show.html.erb`, add `<%= turbo_stream_from @scheduled_job %>` near the top.

- [ ] **Step 4: Channel auth test.**

  `test/channels/jobs_channel_test.rb`:

  ```ruby
  require "test_helper"

  class JobsChannelTest < ActionCable::Channel::TestCase
    test "subscribes to scheduled_job stream when user owns it" do
      stub_connection current_user: users(:one)
      subscribe(scheduled_job_id: scheduled_jobs(:daily_digest).id)
      assert subscription.confirmed?
    end

    test "rejects cross-tenant subscribe" do
      stub_connection current_user: users(:member)
      assert_raises(ActiveRecord::RecordNotFound) do
        subscribe(scheduled_job_id: scheduled_jobs(:daily_digest).id)
      end
    end
  end
  ```

  Run: `bin/rails test test/channels/jobs_channel_test.rb test/models/job_run_broadcast_test.rb -v`
  Expected: PASS.

- [ ] **Step 5: Commit.**

  ```bash
  git add app/channels/jobs_channel.rb \
          app/models/job_run.rb \
          app/views/scheduled_jobs/show.html.erb \
          test/channels/jobs_channel_test.rb \
          test/models/job_run_broadcast_test.rb
  git commit -m "Phase 5 Task 5.13: JobsChannel stream_for scheduled_job + JobRun#after_commit broadcast_replace_to"
  ```

---

## Task 5.14 — `Event.incidents` scope + `Dashboard::Rollup` PORO

Two read-only data shapes the dashboard needs. Keep them out of `DashboardController` so they're independently testable.

**Files:**
- Modify: `app/models/event.rb`
- Create: `app/models/dashboard/rollup.rb`
- Create: `test/models/event_incidents_test.rb`
- Create: `test/models/dashboard/rollup_test.rb`

- [ ] **Step 1: Failing test for `Event.incidents`.**

  ```ruby
  require "test_helper"

  class EventIncidentsTest < ActiveSupport::TestCase
    test "incidents includes error_ events and excludes :reloaded with creator nil" do
      msg = messages(:hello)
      msg.events.create!(action: "message_failed",    creator: users(:one), occurred_at: 1.hour.ago)
      msg.events.create!(action: "message_streamed",  creator: users(:one), occurred_at: 1.hour.ago)
      msg.events.create!(action: "skill_reloaded",    creator: nil,         occurred_at: 1.hour.ago)
      msg.events.create!(action: "tool_call_errored", creator: nil,         occurred_at: 1.hour.ago)

      actions = Event.incidents.pluck(:action)
      assert_includes actions, "message_failed"
      assert_includes actions, "tool_call_errored"
      assert_not_includes actions, "message_streamed"
      assert_not_includes actions, "skill_reloaded"
    end
  end
  ```

  Run: expect FAIL — no `incidents` scope.

- [ ] **Step 2: Add scope.**

  In `app/models/event.rb`:

  ```ruby
  INCIDENT_PATTERNS = %w[
    %_failed
    %_errored
    %_error_%
    error_%
  ].freeze

  scope :incidents, lambda {
    pattern_predicate = INCIDENT_PATTERNS.map { "action LIKE ?" }.join(" OR ")
    where(pattern_predicate, *INCIDENT_PATTERNS)
      .where.not(action: %w[skill_reloaded memory_file_reloaded])
      .order(occurred_at: :desc)
  }
  ```

  Run: PASS.

- [ ] **Step 3: Rollup PORO test.**

  `test/models/dashboard/rollup_test.rb`:

  ```ruby
  require "test_helper"

  class Dashboard::RollupTest < ActiveSupport::TestCase
    test "tokens_by_day groups completed messages by day" do
      msg = messages(:hello)
      msg.update!(status: :completed, prompt_tokens: 100, completion_tokens: 50, cost_usd: "0.01", created_at: 2.days.ago)
      Message.create!(chat_session: msg.chat_session, role: :assistant, status: :completed,
                      content_blocks: [], model: msg.model, provider: msg.provider,
                      prompt_tokens: 200, completion_tokens: 100, cost_usd: "0.02", created_at: 1.day.ago)

      rollup = Dashboard::Rollup.new(scope: Message.where(chat_session: msg.chat_session))
      days   = rollup.tokens_by_day
      assert_equal 2, days.size
      assert(days.all? { |row| row[:tokens] > 0 && row[:cost_usd].to_f > 0 })
    end

    test "cost_by_model sums per model" do
      Message.create!(chat_session: chat_sessions(:one), role: :assistant, status: :completed,
                      content_blocks: [], model: "claude-haiku-4-5", provider: "anthropic",
                      cost_usd: "0.01")
      Message.create!(chat_session: chat_sessions(:one), role: :assistant, status: :completed,
                      content_blocks: [], model: "claude-opus-4-7", provider: "anthropic",
                      cost_usd: "0.15")

      rollup  = Dashboard::Rollup.new(scope: Message.all)
      by_model = rollup.cost_by_model
      assert_equal "0.150000", by_model["claude-opus-4-7"].to_s
    end
  end
  ```

- [ ] **Step 4: Implementation.**

  `app/models/dashboard/rollup.rb`:

  ```ruby
  class Dashboard::Rollup
    DEFAULT_DAYS = 14

    def initialize(scope: Message.all, days: DEFAULT_DAYS)
      @scope = scope.where(status: :completed).where(created_at: days.days.ago..)
    end

    def tokens_by_day
      @scope
        .group(Arel.sql("date(created_at)"))
        .pluck(
          Arel.sql("date(created_at)"),
          Arel.sql("COALESCE(SUM(prompt_tokens + completion_tokens), 0)"),
          Arel.sql("COALESCE(SUM(cost_usd), 0)")
        )
        .map { |day, tokens, cost| { day: day, tokens: tokens.to_i, cost_usd: cost } }
    end

    def cost_by_model
      @scope
        .group(:model)
        .sum(:cost_usd)
        .transform_values(&:to_d)
    end

    def cost_by_session(limit: 10)
      @scope
        .group(:chat_session_id)
        .order(Arel.sql("SUM(cost_usd) DESC"))
        .limit(limit)
        .sum(:cost_usd)
    end
  end
  ```

  Run: `bin/rails test test/models/dashboard/rollup_test.rb test/models/event_incidents_test.rb -v`
  Expected: PASS.

- [ ] **Step 5: Commit.**

  ```bash
  git add app/models/event.rb \
          app/models/dashboard/rollup.rb \
          test/models/event_incidents_test.rb \
          test/models/dashboard/rollup_test.rb
  git commit -m "Phase 5 Task 5.14: Event.incidents scope (drops :reloaded/creator=nil) + Dashboard::Rollup PORO"
  ```

---

## Task 5.15 — `DashboardController#show` + view + chart.js pin

Pull rollups + incidents + MCP status into one page. Chart.js pinned via importmap (no npm install — same CDN pattern as `xterm`).

**Files:**
- Modify: `app/controllers/dashboard_controller.rb`
- Modify: `app/views/dashboard/show.html.erb`
- Modify: `config/importmap.rb`
- Create: `app/javascript/controllers/chart_controller.js`
- Modify: `config/initializers/content_security_policy.rb` (allow esm.sh for chart.js)
- Create: `test/controllers/dashboard_controller_test.rb`

- [ ] **Step 1: Pin chart.js.**

  ```bash
  bin/importmap pin chart.js
  ```

  Verify `config/importmap.rb` adds `pin "chart.js"` (and its deps, e.g. `@kurkle/color`). Pin an exact version per CSP/SRI guidance:

  ```ruby
  pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.4/auto/auto.js"
  pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.2/dist/color.esm.js"
  ```

  (Exact URLs depend on the importmap output — copy verbatim from the generator.)

- [ ] **Step 2: CSP allow esm.sh / jspm.io for script-src + connect-src.**

  In `config/initializers/content_security_policy.rb`, extend the `script_src` allowlist to include `ga.jspm.io` (or whatever host `importmap pin` emitted). Match the existing `xterm` pattern.

- [ ] **Step 3: Failing controller test.**

  `test/controllers/dashboard_controller_test.rb`:

  ```ruby
  require "test_helper"

  class DashboardControllerTest < ActionDispatch::IntegrationTest
    include ControllerSignInHelpers

    test "GET /dashboard renders rollups, incidents, mcp servers, runs" do
      sign_in_as users(:one)
      get root_path  # root → dashboard
      assert_response :success
      assert_select "[data-controller~='chart']"     # one chart container
      assert_select "section.incidents"
      assert_select "section.mcp-status"
      assert_select "section.recent-runs"
    end

    test "dashboard scopes data to current user" do
      sign_in_as users(:member)
      get root_path
      assert_response :success
      # member has no jobs/messages → no run/incident rows.
      assert_select "section.recent-runs li", false
    end
  end
  ```

  Expected: FAIL — sections not present.

- [ ] **Step 4: Controller.**

  ```ruby
  class DashboardController < ApplicationController
    def show
      scope = Message.joins(:chat_session).where(chat_sessions: { user_id: Current.user.id })
      @rollup    = Dashboard::Rollup.new(scope: scope)
      @incidents = Event.incidents
                        .joins("INNER JOIN chat_sessions cs ON cs.id = events.eventable_id AND events.eventable_type = 'ChatSession'")
                        .where(chat_sessions: { user_id: Current.user.id })
                        .limit(20)
                        .or(Event.incidents.where(creator: Current.user).limit(20))
                        .limit(20)
      @recent_runs = JobRun.joins(:scheduled_job)
                           .where(scheduled_jobs: { user_id: Current.user.id })
                           .recent.limit(10)
      @mcp_servers = Current.user.mcp_servers.order(:name)
    end
  end
  ```

  (The `@incidents` query is intentionally explicit — the polymorphic join needs the eventable_type guard. Re-check this against the actual eventable usage in Phase 1–4 events; adjust the join shape if a simpler `Current.user.events` scope exists.)

- [ ] **Step 5: View.**

  `app/views/dashboard/show.html.erb`:

  ```erb
  <% content_for :title, "Dashboard" %>

  <%= turbo_stream_from "dashboard:#{Current.user.id}" %>

  <section class="pad max-width">
    <h1>Dashboard</h1>

    <section class="charts">
      <div data-controller="chart"
           data-chart-type-value="line"
           data-chart-data-value="<%= @rollup.tokens_by_day.to_json %>">
        <canvas></canvas>
      </div>
      <div data-controller="chart"
           data-chart-type-value="bar"
           data-chart-data-value="<%= @rollup.cost_by_model.to_json %>">
        <canvas></canvas>
      </div>
    </section>

    <section class="recent-runs">
      <h2>Recent runs</h2>
      <ul>
        <% @recent_runs.each do |run| %>
          <%= render "scheduled_jobs/runs/run", run: run %>
        <% end %>
      </ul>
    </section>

    <section class="mcp-status">
      <h2>MCP servers</h2>
      <ul>
        <% @mcp_servers.each do |srv| %>
          <li><%= srv.name %> — <span class="badge badge-<%= srv.status %>"><%= srv.status %></span></li>
        <% end %>
      </ul>
    </section>

    <section class="incidents">
      <h2>Incidents</h2>
      <ul>
        <% @incidents.each do |ev| %>
          <li><%= ev.occurred_at.iso8601 %> — <code><%= ev.action %></code> — <%= ev.particulars.to_s.truncate(140) %></li>
        <% end %>
      </ul>
    </section>
  </section>
  ```

- [ ] **Step 6: Stimulus controller.**

  `app/javascript/controllers/chart_controller.js`:

  ```js
  import { Controller } from "@hotwired/stimulus"
  import Chart from "chart.js"

  export default class extends Controller {
    static values = { type: String, data: Object }

    connect() {
      const canvas = this.element.querySelector("canvas")
      this.chart = new Chart(canvas, this.#config())
    }

    disconnect() { this.chart?.destroy() }

    #config() {
      if (this.typeValue === "line") {
        const rows = Array.isArray(this.dataValue) ? this.dataValue : []
        return {
          type: "line",
          data: {
            labels: rows.map(r => r.day),
            datasets: [{ label: "Tokens", data: rows.map(r => r.tokens) }]
          }
        }
      }
      if (this.typeValue === "bar") {
        const rows = this.dataValue || {}
        return {
          type: "bar",
          data: {
            labels: Object.keys(rows),
            datasets: [{ label: "Cost (USD)", data: Object.values(rows) }]
          }
        }
      }
      return { type: this.typeValue, data: {} }
    }
  }
  ```

  Run: `bin/rails test test/controllers/dashboard_controller_test.rb -v`
  Expected: PASS.

- [ ] **Step 7: Commit.**

  ```bash
  git add config/importmap.rb \
          config/initializers/content_security_policy.rb \
          app/controllers/dashboard_controller.rb \
          app/views/dashboard/show.html.erb \
          app/javascript/controllers/chart_controller.js \
          test/controllers/dashboard_controller_test.rb
  git commit -m "Phase 5 Task 5.15: DashboardController#show + chart.js pin + rollups + incidents + MCP status view"
  ```

---

## Task 5.16 — `DashboardChannel` + live rebroadcasts

`stream "dashboard:#{user.id}"`. Three sources rebroadcast:
- `JobRun#after_commit` (already added in Task 5.13 — extend to also broadcast to the dashboard stream).
- `Message#after_commit` (on completion only) to refresh the rollup section.
- `McpServer#after_commit` (status flips) to refresh the status table.

**Files:**
- Create: `app/channels/dashboard_channel.rb`
- Modify: `app/models/job_run.rb`
- Modify: `app/models/message.rb`
- Modify: `app/models/mcp_server.rb`
- Create: `test/channels/dashboard_channel_test.rb`

- [ ] **Step 1: Failing channel test.**

  ```ruby
  require "test_helper"

  class DashboardChannelTest < ActionCable::Channel::TestCase
    test "subscribes to the per-user dashboard stream" do
      stub_connection current_user: users(:one)
      subscribe
      assert_has_stream "dashboard:#{users(:one).id}"
    end
  end
  ```

- [ ] **Step 2: Channel.**

  ```ruby
  class DashboardChannel < ApplicationCable::Channel
    def subscribed
      stream_from "dashboard:#{current_user.id}"
    end
  end
  ```

- [ ] **Step 3: Broadcast from the three sources.**

  In `app/models/job_run.rb`:

  ```ruby
  after_commit -> {
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard:#{scheduled_job.user_id}",
      target:  "dashboard-recent-runs",
      partial: "dashboard/recent_runs",
      locals:  { runs: scheduled_job.user.job_runs.recent.limit(10) }
    )
  }, on: %i[create update]
  ```

  Add `has_many :job_runs, through: :scheduled_jobs` to `User`.

  In `app/models/message.rb`, after_commit on completion → broadcast a rollup partial replace.
  In `app/models/mcp_server.rb`, after_commit (on `saved_change_to_status?`) → broadcast the MCP table partial replace.

  Extract the relevant view markup into partials: `app/views/dashboard/_recent_runs.html.erb`, `_rollups.html.erb`, `_mcp_status.html.erb`. Update `show.html.erb` to render them so the broadcast targets line up.

- [ ] **Step 4: System test (smoke).**

  `test/system/dashboard_test.rb`:

  ```ruby
  require "application_system_test_case"

  class DashboardTest < ApplicationSystemTestCase
    test "dashboard updates when a JobRun finishes" do
      sign_in_as users(:one)
      visit root_path
      assert_text "Dashboard"
      job_runs(:succeeded_one).update!(status: :failed)
      using_wait_time(3) { assert_text "failed" }
    end
  end
  ```

  Run: `bin/rails test:system test/system/dashboard_test.rb -v`
  Expected: PASS (skipped in CI without selenium if needed; document the skip).

- [ ] **Step 5: Commit.**

  ```bash
  git add app/channels/dashboard_channel.rb \
          app/models/job_run.rb \
          app/models/message.rb \
          app/models/mcp_server.rb \
          app/models/user.rb \
          app/views/dashboard/ \
          test/channels/dashboard_channel_test.rb \
          test/system/dashboard_test.rb
  git commit -m "Phase 5 Task 5.16: DashboardChannel + per-user rebroadcasts on JobRun/Message/McpServer commit"
  ```

---

## Task 5.17 — Cron-preview Stimulus + form polish

Tiny UX win: when the user types `0 9 * * *` into the new-job form, show "Next fire: 2026-05-17 09:00 UTC" beneath the input. Pure Stimulus, server-rendered via a `/jobs/cron_preview` JSON endpoint. Keeps the user from saving an invalid cron and getting a model error.

**Files:**
- Modify: `app/controllers/scheduled_jobs_controller.rb`
- Modify: `config/routes.rb`
- Create: `app/javascript/controllers/cron_preview_controller.js`
- Modify: `app/views/scheduled_jobs/_form.html.erb`
- Create: `test/controllers/scheduled_jobs_controller_test.rb` extension

- [ ] **Step 1: Failing test.**

  ```ruby
  test "GET /jobs/cron_preview returns next fire time" do
    sign_in_as users(:one)
    get cron_preview_scheduled_jobs_path, params: { cron: "0 9 * * *" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_match(/\d{4}-\d{2}-\d{2}/, json["next_run_at"])
  end

  test "GET /jobs/cron_preview returns 422 on garbage" do
    sign_in_as users(:one)
    get cron_preview_scheduled_jobs_path, params: { cron: "wut" }
    assert_response :unprocessable_content
  end
  ```

- [ ] **Step 2: Route + controller action.**

  In `config/routes.rb`:

  ```ruby
  resources :scheduled_jobs, path: "jobs" do
    collection do
      get :cron_preview
    end
    ...
  end
  ```

  In `app/controllers/scheduled_jobs_controller.rb`:

  ```ruby
  def cron_preview
    cron = ScheduledJob::Cron.new(params[:cron])
    render json: { next_run_at: cron.next_run_at.iso8601 }
  rescue ScheduledJob::Cron::Invalid, ScheduledJob::Cron::TooFrequent => e
    render json: { error: e.message }, status: :unprocessable_content
  end
  ```

- [ ] **Step 3: Stimulus controller** (`app/javascript/controllers/cron_preview_controller.js`) — 30 lines: debounced fetch, sets a target's text content. Same pattern as Task 5.2's autocomplete.

- [ ] **Step 4: Wire into `_form.html.erb`.** Input gets `data-controller="cron-preview"` + a `<output data-cron-preview-target="result">` below it.

- [ ] **Step 5: Commit.**

  ```bash
  git add config/routes.rb \
          app/controllers/scheduled_jobs_controller.rb \
          app/javascript/controllers/cron_preview_controller.js \
          app/views/scheduled_jobs/_form.html.erb \
          test/controllers/scheduled_jobs_controller_test.rb
  git commit -m "Phase 5 Task 5.17: /jobs/cron_preview endpoint + Stimulus preview controller"
  ```

---

## Task 5.18 — End-to-end system test

Schedule a daily prompt, manually fire it, view the run, view the dashboard. This is the exit-criteria proof.

**Files:**
- Create: `test/system/scheduled_jobs_test.rb`

- [ ] **Step 1: System test.**

  ```ruby
  require "application_system_test_case"

  class ScheduledJobsTest < ApplicationSystemTestCase
    test "user creates a job, runs it manually, sees the run on the dashboard" do
      # Stub the LLM adapter so the run completes deterministically.
      stub_llm_adapter_with_completion("Run output text.")

      sign_in_as users(:one)
      visit scheduled_jobs_path
      click_on "New job"

      fill_in "Name",   with: "Daily summary"
      fill_in "Cron",   with: "0 9 * * *"
      fill_in "Prompt", with: "Hi"
      click_on "Create"

      assert_text "Job scheduled."
      click_on "Run now"
      assert_text "Run queued."

      # Drive the inline adapter; with Solid Queue inline-mode tests the run completes synchronously.
      using_wait_time(5) { assert_text "succeeded" }

      visit root_path  # dashboard
      assert_text "Daily summary"
      assert_text "succeeded"
    end
  end
  ```

  (Stub helper lives in `test/support/llm_stubs.rb` — same pattern as Task 5.9's runnable test.)

  Run: `bin/rails test:system test/system/scheduled_jobs_test.rb -v`
  Expected: PASS.

- [ ] **Step 2: Commit.**

  ```bash
  git add test/system/scheduled_jobs_test.rb test/support/llm_stubs.rb
  git commit -m "Phase 5 Task 5.18: end-to-end system test (create → run → dashboard)"
  ```

---

## Task 5.19 — Phase 5 exit criteria + verification

- [ ] **Schedule a daily prompt, see it run, view output, see costs on dashboard.** Covered by `test/system/scheduled_jobs_test.rb` (Task 5.18).
- [ ] **Pause/resume changes scheduler dispatch.** Covered by `test/jobs/scheduler_tick_job_test.rb` (Task 5.8).
- [ ] **Cron validation rejects bad / sub-minute schedules.** `test/models/scheduled_job/cron_test.rb` (Task 5.7).
- [ ] **`ScheduledJob#run!` captures success + failure paths to JobRun.** `test/models/scheduled_job/runnable_test.rb` (Task 5.9).
- [ ] **Dashboard renders incidents, MCP status, rollups, recent runs.** `test/controllers/dashboard_controller_test.rb` (Task 5.15).
- [ ] **JobRun status flips broadcast to JobsChannel + DashboardChannel.** `test/models/job_run_broadcast_test.rb` + `test/system/dashboard_test.rb` (Tasks 5.13, 5.16).
- [ ] **Phase 3 carry-overs closed.** Tasks 5.1 (FTS lift), 5.2 (prefix search + autocomplete), 5.3 (live /skills), 5.4 (drop redundant timestamps), 5.14 (incidents scope filters reloaded creator-nil).
- [ ] **All tests pass:**

  ```bash
  bin/rails db:migrate db:test:prepare
  bin/rails test
  bin/rails test:system
  bin/bundle exec brakeman -A
  bin/bundle exec bundler-audit check --update
  ```

  Expected: tests green; brakeman count = Phase 4 baseline + 0 new (Dashboard query string interpolation flagged → use bound parameters; chart.js importmap doesn't add new file-access warnings). Bundler-audit: 0 vulnerabilities. Record the new run/assertion totals — Phase 6 verification compares against these, not Phase 4's.

- [ ] **Tag `phase-5`.** `git tag phase-5` after the hardening gate closes.

---

## Phase 5 hardening gate (must-fix before tagging)

Mirrors the Phase 3 / 4 H-series structure. Predicted from the plan; refine after a 4-parallel-agent code review (Task 5.20-style follow-up batch).

- [ ] **H1 — Scheduler dispatch is idempotent under crash recovery.** If `RunnerJob` crashes after `JobRun.create!(status: :running)` but before `#run!` returns, the row is stuck `:running` forever. Add `JobRun.sweep_stale!` (any row with `status: :running` and `started_at < 1.hour.ago` flips to `:failed` with `error_message: "stale — supervisor died mid-run"`). Recurring entry alongside `scheduler_tick`. Test: insert a `:running` row dated 2h ago, run the sweep, assert it's `:failed`.

- [ ] **H2 — Cross-tenancy on JobsChannel + DashboardChannel + every `/jobs/*` route.** A user subscribed to another user's `JobsChannel.stream_for(scheduled_job)` must be rejected; `/jobs/<other-user-id>` returns 404; `/jobs/<a-id>/runs` returns 404 for user B. Follow the Phase 1 `test/controllers/concerns/cross_tenancy_assertions.rb` pattern.

- [ ] **H3 — JobRun output cap is enforced + measured.** Task 5.9 truncates at 256 KiB but doesn't surface the original size. Add `JobRun#output_truncated_at_bytes` (nullable integer) and store the original size when truncation kicks in. The show page renders a "Full output truncated — chat session has the complete transcript" banner. Test: a stub adapter that returns >256 KiB → assert truncation marker present + banner rendered.

- [ ] **H4 — `Event.incidents` SQL injection probe.** The scope uses `LIKE ?` with bound parameters — no concat — but document the test that proves it: pass `action: "foo'); DROP TABLE messages;--"` to an event row and assert the query still runs cleanly + the row appears.

- [ ] **H5 — Chart.js CSP + SRI.** Importmap pin emits a `ga.jspm.io` URL. Add `integrity:` to the pin (Rails 8 supports it). CSP: `script_src` must allowlist the host; `connect-src` must not (chart.js doesn't make XHR). Verify: tampered CDN bundle → browser refuses to load. Document the rotation cost (every chart.js version bump requires a new SRI hash).

- [ ] **H6 — Dashboard query plan.** `Dashboard::Rollup` uses `date(created_at)` in the GROUP BY — SQLite can't index a function expression by default. Add an `index_messages_on_created_at` if missing (Phase 1 indexed `[chat_session_id, created_at]` but not `created_at` alone). Run `EXPLAIN QUERY PLAN` against the rollup queries and document any full table scans.

- [ ] **H7 — Pause/run race.** Scheduler tick at second 0; user clicks Pause at second 0+ε; the tick may already have enqueued. Two acceptable resolutions: (a) `ScheduledJob::RunnerJob#perform` re-checks `paused?` before delegating to `#run!`; (b) accept that one extra run can leak past pause. Pick (a) — implement + test by stubbing the gap.

- [ ] **H8 — `ScheduledJob::Cron::TooFrequent` covers `@hourly`-style + every fugit shortcut.** Today the heuristic computes two successive `next_time` values and checks the delta. Verify it correctly rejects `* * * * *` (60s — borderline but acceptable), `*/30 * * * * *` (sub-minute → reject), and accepts `0 * * * *` (hourly).

- [ ] **H9 — `Skill#after_commit { broadcast_replace_to "skills" }` doesn't broadcast on body-only updates.** Task 5.3 broadcasts on every `update`. The watcher fires `Skill::ReloadJob` on disk writes that don't change the row (body unchanged) — Loadable's digest guard short-circuits before `update!`, so no broadcast. But a digest change without a name change still broadcasts the full partial — fine. Test: rapid-fire 10 reloads of the same skill → exactly 1 broadcast (digest guard) + 1 if anything actually changed.

- [ ] **H10 — `SchedulerTickJob` concurrency lock.** If two web workers somehow enqueue duplicate ticks (clock drift, recurring config race), `ScheduledJob.run_all_due` could double-enqueue `RunnerJob`. Use Solid Queue's `limits_concurrency key: "scheduler_tick", to: 1`. Or — simpler — leave it alone, accept that a duplicate `RunnerJob.perform_later` inside a transaction is cheap, and rely on H7's paused check to dedupe. Decide in the code review.

- [ ] **H11 — Dashboard incidents scope leak across tenants.** Today `Event.incidents` is global. The dashboard joins to `chat_sessions.user_id = Current.user.id`, but the join misses incidents on `eventable_type IN (Skill, McpServer, ScheduledJob)`. Tighten the dashboard query to a UNION over each owned eventable scope, or constrain `Event.incidents` to take a `for_user:` argument.

- [ ] **H12 — `JobRun.output` doesn't capture provider-side errors that arrive without a text block.** If the adapter raises before any `:text_delta`, `extract_text_output` returns `""`. The `error_message` is captured but the show view should fall back gracefully (the `failed` path renders `@run.error_message`; verify the empty-output path doesn't render an empty `<pre>` block).

---

## Task 5.20 — Post-review fix-ups (Phase 5 batch 2) — placeholder

After the hardening gate closes and `phase-5` is tagged, schedule a code review (4 parallel agents per the Phase 3 / 4 pattern). The likely surface:

- `Dashboard::Rollup` query performance under 100k+ messages — index changes or materialized rollup table.
- `JobsChannel` reconnect behaviour during a long-running job (the show page might miss the `succeeded` broadcast if the user navigates away and back); replay from `JobRun.recent.limit(N)` on resubscribe.
- `ScheduledJob::Cron::TooFrequent` heuristic edge cases (year-based fugit expressions, second-resolution shortcuts).
- Chart.js bundle size — likely 200+ KiB gzipped; consider lazy-load only on `/dashboard` rather than eager-pinning in `application.js`.
- The dashboard's `@incidents` UNION query is intricate — extract to `User#incidents_feed` if it grows.

Land as one or two grouped commits mirroring 3.16a/b/c. Retag `phase-5` to the green tree.

---

## Phase 5.5 — Slip candidates (defer if scope balloons)

If Phase 5 runs hot, slip these to a Phase 5.5 follow-up doc:

1. **Materialized rollup table.** `dashboard_rollups` aggregated nightly by a recurring job. Required only if `Dashboard::Rollup` shows hot-path cost.
2. **Per-skill / per-agent-profile filtering in `ScheduledJob#run!`.** Today `#run!` uses `Tool::Internal` defaults + the user's enabled skills. Per-job skill selection ships with Phase 6's `agent_profile_skills`.
3. **Job notifications.** Email/webhook on `JobRun.failed` ("your daily-digest broke at 09:00"). Notification infra is Phase 7.
4. **Cron-friendly retry policy.** A `RunnerJob` failure today writes `JobRun.failed` and moves on. A real ops surface wants exponential backoff (retry 3×, then fail). Phase 5.5 or Phase 7.
5. **Dashboard date-range picker.** Today the rollup is hard-coded to 14 days. A picker (this week / 30 days / custom) is low-cost but not on the exit criteria.

---

## Critical files map (Phase 5 additions)

```
config/routes.rb                                         # +scheduled_jobs, +dashboard, +pauses, +runs, +cron_preview
config/recurring.yml                                     # +scheduler_tick (every 1 minute)
config/importmap.rb                                      # +chart.js, +@kurkle/color
config/initializers/content_security_policy.rb          # +ga.jspm.io in script_src

db/migrate/<ts>_drop_redundant_timestamps.rb
db/migrate/<ts>_create_scheduled_jobs.rb
db/migrate/<ts>_create_scheduled_job_pauses.rb
db/migrate/<ts>_create_job_runs.rb
db/content_migrate/<ts>_add_prefix_to_fts_tables.rb

app/models/scheduled_job.rb
app/models/scheduled_job/pause.rb
app/models/scheduled_job/pausable.rb
app/models/scheduled_job/cron.rb
app/models/scheduled_job/runnable.rb
app/models/job_run.rb
app/models/dashboard/rollup.rb
app/models/concerns/searchable.rb                       # refactored to own FTS writes
app/models/event.rb                                      # +incidents scope
app/models/user.rb                                       # +has_many :scheduled_jobs, :job_runs
app/models/skill.rb                                      # +after_commit broadcast_replace_to "skills"
app/models/skill/loadable.rb                             # FTS calls dispatch to Searchable
app/models/memory_file.rb                                # include Searchable
app/models/memory_file/reindexable.rb                    # FTS calls dispatch to Searchable
app/models/skill/installable.rb                          # drop accepted_at = Time.current
app/models/skill/enableable.rb                           # drop enabled_at = Time.current
app/models/job_run.rb                                    # +broadcast_replace_to scheduled_job + dashboard
app/models/message.rb                                    # +after_commit dashboard rebroadcast
app/models/mcp_server.rb                                 # +after_commit dashboard rebroadcast

app/controllers/scheduled_jobs_controller.rb
app/controllers/scheduled_jobs/pauses_controller.rb
app/controllers/scheduled_jobs/runs_controller.rb
app/controllers/concerns/scheduled_job_scoped.rb
app/controllers/dashboard_controller.rb                 # rewritten

app/channels/skills_channel.rb
app/channels/jobs_channel.rb
app/channels/dashboard_channel.rb

app/jobs/scheduler_tick_job.rb
app/jobs/scheduled_job/runner_job.rb

app/views/scheduled_jobs/{index,new,edit,show,_form,_scheduled_job_row}.html.erb
app/views/scheduled_jobs/runs/{index,show,_run}.html.erb
app/views/dashboard/{show,_recent_runs,_rollups,_mcp_status,_incidents}.html.erb
app/views/skills/{index,_skill}.html.erb

app/javascript/controllers/autocomplete_controller.js
app/javascript/controllers/chart_controller.js
app/javascript/controllers/cron_preview_controller.js

test/fixtures/scheduled_jobs.yml
test/fixtures/scheduled_job_pauses.yml
test/fixtures/job_runs.yml
test/models/concerns/searchable_test.rb
test/models/scheduled_job_test.rb
test/models/scheduled_job/cron_test.rb
test/models/scheduled_job/runnable_test.rb
test/models/job_run_test.rb
test/models/job_run_broadcast_test.rb
test/models/skill_broadcast_test.rb
test/models/event_incidents_test.rb
test/models/dashboard/rollup_test.rb
test/channels/skills_channel_test.rb
test/channels/jobs_channel_test.rb
test/channels/dashboard_channel_test.rb
test/controllers/scheduled_jobs_controller_test.rb
test/controllers/scheduled_jobs/pauses_controller_test.rb
test/controllers/scheduled_jobs/runs_controller_test.rb
test/controllers/dashboard_controller_test.rb
test/jobs/scheduler_tick_job_test.rb
test/system/scheduled_jobs_test.rb
test/system/dashboard_test.rb
test/support/llm_stubs.rb
```

---

## Open items (Phase 5 only — surface as you hit them, don't pre-decide)

- **Recurring `JobRun.sweep_stale!` vs Solid Queue's own dead-job sweeper.** Solid Queue tracks job liveness; in theory a `RunnerJob` that dies mid-flight gets a Solid Queue failure record. The `JobRun` row is independent — the row says `:running` even after Solid Queue declares the job dead. H1 closes this with our own sweeper. If a future Solid Queue release exposes the dead-job event as an ActiveSupport notification, swap to that and drop the sweeper.

- **Where dashboard rollups live as data grows.** `Dashboard::Rollup` runs three GROUP BY queries on `messages` per dashboard load. Under 100k messages it's fine; past that, a nightly materialized `dashboard_rollups` table beats the live query. Don't pre-decide — measure when the suite or the operator complains.

- **Chart.js vs server-rendered SVG.** Chart.js is the docs default (workflows.md:3035) but a server-rendered SVG (one route, no JS) would be lighter and CSP-trivial. Stay with chart.js for now; revisit if the importmap pin's SRI cost or CSP exemption becomes painful.

- **`Event.incidents` retention.** Events table grows monotonically. No retention policy yet (workflows.md § 19 mentions cost retention on `Message`). Add a recurring `Event.prune!` job in Phase 6 or 7 — Phase 5's exit criteria don't require it.

- **Per-user scheduler quota.** A user could create 1000 `ScheduledJob` rows with `* * * * *` cadence and DoS the queue. `Cron::TooFrequent` rejects sub-minute, but 1000 jobs × 1 minute is still 1000 enqueues/minute. Add a per-user count cap (`MOP_MAX_SCHEDULED_JOBS_PER_USER`, default 50) only if the operator surface needs it.

- **JobsChannel reconnect behaviour.** Same gap workflows.md § 19 calls out for chat. Mid-run navigation away + back loses any broadcast that fired in between. Replay from `JobRun.last_n` on resubscribe — Phase 5.5 candidate.

- **Skill broadcast `:reloaded` event suppression vs creator attribution.** Task 5.14 filters `:reloaded` events with `creator: nil` out of incidents. The underlying watcher-fired events still exist — they're just hidden from the dashboard. If the operator surface ever needs an "automation audit log", surface them under a different scope (`Event.system`).

- **Cross-cutting `_now`/`_later` for ScheduledJob#run!.** The pattern doc (`patterns-and-best-practices.md §4.4`) says every transition has both sync (`_now`) and async (`_later`) entry points. ScheduledJob's `#run!` is sync (the runner job calls it). There's no obvious `_later` caller for Phase 5 — `RunnerJob` *is* the `_later`. Leave it alone unless a controller wants a "run-this-job-asynchronously" path.

---

## Decisions logged during Phase 5 planning

These look like open questions but were closed during this plan — not deferred, decided.

- **Drop `accepted_at` + `enabled_at` outright (not repurpose).** Workflows.md:3040 left both options open. Both columns always equal `created_at` today and no caller distinguishes them; repurposing `enabled_at` for "last re-enable" would invent a use case nobody asked for. Drop and use `created_at`.

- **`:reloaded` events with `creator: nil` are filtered, not attributed to a system user.** Workflows.md:3041 offered both. A `system` pseudo-User row breaks the `belongs_to :creator, optional: true` contract — creating a fake row for non-attribution is more friction than the filter (`where.not(action: ["skill_reloaded", "memory_file_reloaded"])`). Filter wins.

- **Chart.js via importmap CDN pin (not gem-packaged).** Matches the workflows.md § 13 default (esm.sh ESM). Bundle size acceptable; CSP cost (one host added to script_src) is contained.

- **`ScheduledJob::Cron::TooFrequent` floor = 60s.** SchedulerTickJob fires every 60s; finer cron resolution is meaningless. A second-resolution job (`* * * * * *`) gets rejected on save. Rejecting at the model is cheaper than discovering it at dispatch time.

- **`JobRun.output` cap = 256 KiB.** Single-row text column; bigger would bloat the table and DB cache. 256 KiB is generous (a 10k-token output is ~40 KiB). Larger output → still visible in the underlying `ChatSession` linked from the run page.

- **`SchedulerTickJob.run_all_due` does NOT take a `:user_id` parameter.** Single-tenant scheduler tick is global; cross-tenancy is enforced at the row level (every `ScheduledJob` row has `user_id`). A per-user tick would multiply the recurring jobs by tenant count.

- **`Dashboard::Rollup` is a PORO, not an AR scope.** The three aggregations (`tokens_by_day`, `cost_by_model`, `cost_by_session`) are read-only, parameterizable by `:scope` (so the dashboard can pass a tenant-scoped scope), and easier to swap for a materialized table later. AR scopes would lock the shape to `Message`.

- **`JobsChannel` is per-`ScheduledJob`, `DashboardChannel` is per-user.** Two different streams because their read sets differ — the jobs page cares about one row's runs; the dashboard cares about all of the user's data. Don't unify them.

---

## Self-review checklist (planning)

- [x] **Spec coverage** — every workflows.md § Phase 5 deliverable maps to a task above (or is explicitly marked 5.5).
- [x] **Phase 3 carry-overs explicit** — FTS lift (5.1), FTS prefix search (5.2), live /skills (5.3), drop accepted_at/enabled_at (5.4), reloaded-event filter (5.14).
- [x] **Phase 4 epilogue acknowledged** — Task 5.0 names the three follow-up commits since `phase-4`, pins the baseline rather than reusing the Phase 4 numbers.
- [x] **Concrete file paths** — every task names the file it touches.
- [x] **Failing test first** — each task starts from a red test, not from an implementation sketch.
- [x] **Verification commands present** — every task ends with a runnable assertion + expected output.
- [x] **Hardening gate predicted** — 12 items that mirror Phase 3 / 4's H1–H12.
- [x] **Open items separate from decisions** — workflows.md § 19 open items (job retention, per-user quota, materialization, cable replay) surface here, not pre-decided.
- [x] **Scope budget realistic** — Phase 5 / 5.5 split documented; exit criteria hold without 5.5 work (materialization, retries, notifications, picker).
- [x] **Cross-tenancy** — every controller / channel has an explicit cross-tenancy test referenced in H2.
- [x] **State-change child tables** — `scheduled_job_pauses` follows the `chat_session_archives` pattern (Pause + Pausable concern), not an enum flip.
- [x] **No interpolated SQL** — `Dashboard::Rollup` uses `Arel.sql` for safe column literals only; `Event.incidents` uses bound `?` placeholders.
- [x] **3-line jobs preserved** — `SchedulerTickJob`, `ScheduledJob::RunnerJob` are both single-method wrappers per workflows § 10.
