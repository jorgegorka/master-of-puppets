# Phase 2 — Memory + Files + Theme switcher

> **Executor:** Use `superpowers:subagent-driven-development` (or `superpowers:executing-plans`) to drive these tasks one at a time. Each `- [ ]` step has file paths, a failing test, the minimal impl, the verification command + expected output, and a commit. Tick the box as you complete each step.

**Parent plan:** [`docs/plans/workflows.md`](workflows.md) § Phase 2.

**Goal:** edit memory markdown in the browser, persist to disk, full-text-search returns snippets; file browser lists the workspace tree with a traversal guard; theme switch persists across reloads.

**Adds (high level):**

- Wire `Rails.application.config.x.mop_home` + boot the workspace tree (`memory/`, `skills/`, `profiles/`, `artifacts/`, `logs/`).
- `WorkspacePath` value object — single guard for every disk read/write.
- `memory_files` on `primary` + `memory_files_fts` virtual table on `content`.
- `MemoryFile` model with `Reindexable`, `Writable`, `Searchable` concerns + `Eventable`.
- `Memory::IndexerJob` (3-line wrapper).
- Memory page: tree + show + edit + search (textarea editor; Monaco upgrade is Phase 4).
- `WorkspaceFile.tree(root:, ...)` + Files page (tree + read + write, textarea editor).
- `theme_controller.js` + Settings UI for theme/accent.
- `bin/agents_supervisor` v1: `listen` watcher for `${MOP_HOME}/memory/`, posts `memory.changed` over the UNIX-socket bridge back to a Rails-side enqueuer that fires `Memory::IndexerJob`.

**Exit criteria:** see Task 2.12.

---

## Task 2.0 — Phase 1 cleanup (deferred review findings)

These were called out in workflows.md § Phase 2 "Phase 1 cleanup". Land them first so Phase 2 work doesn't compound on the same rough edges.

- [x] **Step 1: Collapse `Message::Streamable#needs_tool_loop?` N×`exists?` into one query.**

  Hydrate the in-memory `Set` of succeeded `provider_tool_id`s for this message in a single `pluck`, then check each `tool_use` block against the set. Add a model test that creates 3 succeeded `ToolCall`s + 1 `tool_use` block missing a counterpart and asserts the method returns `true` with exactly 1 SQL query (use `assert_queries_count 1`, Rails 8.1's built-in matcher).

- [x] **Step 2: Downgrade `ChatChannel#subscribed` to a logged `reject`.**

  Replace the implicit `RecordNotFound` raise (from `Current.user.chat_sessions.find(params[:chat_session_id])`) with `find_by` + `reject` + `Rails.logger.info`. Update the channel test that currently expects a raise to assert `subscription.rejected?`.

- [x] **Step 3: Replace the empty `Message::Costable` placeholder.** *(option (a) — moved `compute_cost` + added `total_tokens` to Costable.)*

  Pick one (Phase 2 task list owns the decision):
  - **(a)** Move `compute_cost` + the four token attribute helpers out of `Message::Streamable` into `Message::Costable`. Update `Message` includes; tests stay green.
  - **(b)** Delete `app/models/message/costable.rb` entirely and remove the `include Message::Costable` from `Message`. The placeholder is gone with zero behaviour change.

  Default to **(a)** — it matches the concern-per-capability pattern in `docs/patterns-and-best-practices.md` and keeps `Streamable` focused on the stream loop.

- [x] **Step 4: Share the model dropdown source.**

  Add `Llm::Pricing.models_for(provider)` returning the array of model IDs from the pricing table. Use it in `chat_sessions/new.html.erb` for the model dropdown and in `ChatSessionsController#new` for the default-model fallback. The `ENV["MOP_DEFAULT_MODEL"]` env var stays as an override but must be one of `models_for("anthropic")` (validate at boot in `config/initializers/llm_pricing_check.rb` — fail loud on a typo).

- [x] **Step 5: Deep-freeze `Llm::Pricing::TABLE`.**

  ```ruby
  TABLE = { "claude-opus-4-7" => { input: …, output: … }, … }
            .transform_values(&:freeze)
            .freeze
  ```

  No behaviour change; protects against a downstream mutation.

- [x] **Step 6: Run + commit** — `bin/rails test` 60 runs, 0 failures; system tests green; committed as `b70a605`.

---

## Task 2.1 — `Rails.application.config.x.mop_home` + workspace bootstrap

The single source of truth for `${MOP_HOME}`. Every disk-touching model reads from `Rails.application.config.x.mop_home` — never `ENV["MOP_HOME"]` directly outside this file.

- [x] **Step 1: Set `config.x.mop_home` in `config/application.rb`.**

  Inside the `class Application < Rails::Application` block, after `config.autoload_lib`:

  ```ruby
  config.x.mop_home = ENV.fetch("MOP_HOME") { Rails.root.join("storage/workspace").to_s }
  ```

- [x] **Step 2: Bootstrap the workspace tree on boot.** *(extracted the body into `WorkspaceBootstrap.run(root)` so tests can call it directly against `Dir.mktmpdir`.)*

  New initializer `config/initializers/workspace_bootstrap.rb`:

  ```ruby
  Rails.application.config.after_initialize do
    next if Rails.env.test?  # tests manage their own MOP_HOME via fixtures

    root = Pathname.new(Rails.application.config.x.mop_home)
    %w[memory skills profiles artifacts logs].each do |sub|
      FileUtils.mkdir_p(root.join(sub))
    end

    memory_md = root.join("memory/MEMORY.md")
    File.write(memory_md, "# Memory\n\nIndex of memory notes.\n") unless memory_md.exist?
  end
  ```

  Why `unless Rails.env.test?`: tests use `Dir.mktmpdir` per test where they need a real workspace; we don't want every test boot creating `storage/workspace/`.

- [x] **Step 3: Tests for the bootstrap.** 3 tests, 8 assertions: subdirs created, seed file written, idempotent across repeat runs, no clobber of edited `MEMORY.md`.

- [x] **Step 4: Commit** — `92bf39f`.

---

## Task 2.2 — `WorkspacePath` value object

Single guard for every disk read/write. Refuses anything that escapes `${MOP_HOME}` after `File.realpath`. Lives at `app/models/workspace_path.rb` (per `docs/patterns-and-best-practices.md` value-objects-go-in-app/models).

- [x] **Step 1: Failing tests** at `test/models/workspace_path_test.rb` (9 tests; backslash + not-yet-existing-path cases added on top of the original spec):

  ```ruby
  require "test_helper"

  class WorkspacePathTest < ActiveSupport::TestCase
    setup do
      @tmp = Dir.mktmpdir
      @prev_home = Rails.application.config.x.mop_home
      Rails.application.config.x.mop_home = @tmp
      FileUtils.mkdir_p(File.join(@tmp, "memory/notes"))
      File.write(File.join(@tmp, "memory/notes/a.md"), "hi")
    end

    teardown do
      FileUtils.rm_rf(@tmp)
      Rails.application.config.x.mop_home = @prev_home
    end

    test "resolves a clean path under root" do
      path = WorkspacePath.resolve(root: "memory", raw: "notes/a.md")
      assert_equal File.realpath(File.join(@tmp, "memory/notes/a.md")), path.to_s
    end

    test "refuses traversal via .." do
      assert_raises(WorkspacePath::EscapeAttempt) do
        WorkspacePath.resolve(root: "memory", raw: "../../../etc/passwd")
      end
    end

    test "refuses absolute paths" do
      assert_raises(WorkspacePath::EscapeAttempt) do
        WorkspacePath.resolve(root: "memory", raw: "/etc/passwd")
      end
    end

    test "refuses symlinks that point outside the root" do
      File.symlink("/etc", File.join(@tmp, "memory/escape"))
      assert_raises(WorkspacePath::EscapeAttempt) do
        WorkspacePath.resolve(root: "memory", raw: "escape/passwd")
      end
    end

    test "refuses null byte injection" do
      assert_raises(WorkspacePath::EscapeAttempt) do
        WorkspacePath.resolve(root: "memory", raw: "notes/a.md\0/etc/passwd")
      end
    end

    test "rel returns path relative to the named root" do
      path = WorkspacePath.resolve(root: "memory", raw: "notes/a.md")
      assert_equal "notes/a.md", path.rel
    end
  end
  ```

- [x] **Step 2: Implement** `app/models/workspace_path.rb`. *(Final form differs from the spec: the textual `cleanpath` check runs **before** `realpath` to avoid ENOENT on a parent that lives outside the workspace; a second post-realpath check still catches symlinks. Backslashes are explicitly rejected — closes the "rejects Windows backslashes" item from the hardening gate.)*

  ```ruby
  class WorkspacePath
    class EscapeAttempt < StandardError; end

    attr_reader :absolute, :rel, :root_key

    def self.resolve(root:, raw:)
      new(root: root, raw: raw)
    end

    def initialize(root:, raw:)
      raise EscapeAttempt, "null byte" if raw.to_s.include?("\0")
      raise EscapeAttempt, "absolute path" if Pathname.new(raw).absolute?
      @root_key = root
      base = Pathname.new(File.join(Rails.application.config.x.mop_home, root)).realpath
      candidate = base.join(raw)
      @absolute =
        if candidate.exist?
          candidate.realpath
        else
          # For paths that don't exist yet (e.g. a new file we're about to
          # write), realpath the parent and append the basename.
          parent = candidate.dirname
          parent.realpath.join(candidate.basename)
        end
      unless @absolute.to_s.start_with?(base.to_s + File::SEPARATOR) || @absolute == base
        raise EscapeAttempt, "#{raw.inspect} escapes #{root}"
      end
      @rel = @absolute.relative_path_from(base).to_s
    end

    def to_s = absolute.to_s
    def to_pathname = absolute
    def read = File.read(absolute)
    def exist? = absolute.exist?
  end
  ```

- [x] **Step 3: Pass + commit** — `f355938`. 72 tests / 173 assertions, brakeman 0 warnings.

---

## Task 2.3 — `memory_files` table + `MemoryFile` model

`primary` DB table. The body lives on disk at `${MOP_HOME}/memory/<path>`; the row is an index/cache.

- [x] **Step 1: Migration**

  ```bash
  bin/rails g migration CreateMemoryFiles
  ```

  Edit:

  ```ruby
  class CreateMemoryFiles < ActiveRecord::Migration[8.1]
    def change
      create_table :memory_files do |t|
        t.string  :path,           null: false
        t.string  :title
        t.json    :tags,           default: []
        t.string  :content_digest, null: false
        t.integer :byte_size,      null: false
        t.datetime :disk_mtime,    null: false
        t.timestamps
      end
      add_index :memory_files, :path, unique: true
      add_index :memory_files, :disk_mtime
    end
  end
  ```

- [x] **Step 2: Model** at `app/models/memory_file.rb`:

  ```ruby
  class MemoryFile < ApplicationRecord
    include Eventable

    validates :path, presence: true, uniqueness: true

    scope :recently_changed, -> { order(disk_mtime: :desc) }

    def workspace_path
      WorkspacePath.resolve(root: "memory", raw: path)
    end

    def body
      workspace_path.read
    end
  end
  ```

  No `Reindexable`/`Writable`/`Searchable` yet — they land in Tasks 2.4–2.6 with their own concerns.

- [x] **Step 3: Tests** at `test/models/memory_file_test.rb` — 4 tests cover uniqueness, body round-trip, traversal rejection, and the `recently_changed` scope.

- [x] **Step 4: Fixtures** at `test/fixtures/memory_files.yml`:

  ```yaml
  index:
    path: MEMORY.md
    title: Memory
    tags: []
    content_digest: <%= Digest::SHA256.hexdigest("# Memory\n") %>
    byte_size: 10
    disk_mtime: <%= 1.day.ago.utc %>
  ```

  Note: the fixture is metadata only — tests that touch `body` must create the file in `setup`.

- [x] **Step 5: Run + commit** — `dd8a42e`. 76 tests / 179 assertions.

---

## Task 2.4 — `memory_files_fts` virtual table + `Searchable` concern

FTS5 virtual table on the `content` database. Searchable from `MemoryFile`, with `Skill` + `Message` joining the same concern in later phases.

- [x] **Step 1: Content migration** — switched from raw `execute` SQL to the Rails 8 `create_virtual_table :memory_files_fts, :fts5, COLUMNS` helper so schema dumps survive (the raw form trips the SQLite schema dumper on multi-line `CREATE VIRTUAL TABLE … USING …(…)` SQL).

- [x] **Step 2: `ContentRecord` abstract base** at `app/models/content_record.rb` (per workflows.md § 4.3):

  ```ruby
  class ContentRecord < ApplicationRecord
    self.abstract_class = true
    connects_to database: { writing: :content, reading: :content }
  end
  ```

- [x] **Step 3: `MemoryFileFts` virtual model** at `app/models/memory_file_fts.rb`:

  ```ruby
  class MemoryFileFts < ContentRecord
    self.table_name = "memory_files_fts"
    self.primary_key = nil
  end
  ```

- [x] **Step 4: `Searchable` concern** at `app/models/concerns/searchable.rb` (shared, but Phase 2 only wires `MemoryFile`). *(Spec's `instr(...)` ordering trick rewritten as an after-load `index_by`/`filter_map` — same one-shot SQL for the FTS query, simpler ordering on the Ruby side, returns an Array consistently.)*

  ```ruby
  module Searchable
    extend ActiveSupport::Concern

    class_methods do
      def matching(query)
        return none if query.blank?
        sanitized = query.to_s.gsub('"', '""')
        ids = MemoryFileFts
          .where("memory_files_fts MATCH ?", "\"#{sanitized}\"")
          .order(Arel.sql("bm25(memory_files_fts)"))
          .limit(50)
          .pluck(:memory_file_id)
        where(id: ids).order(Arel.sql("instr(',' || ? || ',', ',' || id || ',')").gsub("?", ids.join(",").presence || "0"))
      end
    end
  end
  ```

  *(If the `instr` ordering trick reads awkward, replace it with an `index_with` after-load sort — but the SQL form keeps the query in one shot.)*

- [x] **Step 5: Tests** at `test/models/memory_file_search_test.rb` — 4 tests cover bm25 ordering, blank/nil → `[]`, no-match → `[]`, and embedded-quote safety.

- [x] **Step 6: Commit** — `5ec8483`. 80 tests / 190 assertions.

---

## Task 2.5 — `Reindexable` concern + `Memory::IndexerJob`

Single-file reindex (`reindex!`) and whole-tree walk (`reindex_all`). Keeps the FTS row in sync with disk.

- [x] **Step 1: Concern** at `app/models/memory_file/reindexable.rb`. *(Spec extended: short-circuit when `content_digest` is unchanged so repeat runs don't churn the FTS row; `after_destroy_commit` clears the FTS row on row destroy. Both behaviours back the Task 2.5/2.12 hardening-gate idempotency item.)*

  ```ruby
  module MemoryFile::Reindexable
    extend ActiveSupport::Concern

    class_methods do
      def reindex_all
        root = Pathname.new(Rails.application.config.x.mop_home).join("memory")
        seen = []
        Pathname.glob(root.join("**/*.md")).each do |file|
          rel = file.relative_path_from(root).to_s
          MemoryFile.reindex(rel)
          seen << rel
        end
        MemoryFile.where.not(path: seen).delete_all  # tombstone deleted files
        seen
      end

      def reindex(path)
        file = MemoryFile.find_or_initialize_by(path: path)
        file.reindex!
      end
    end

    def reindex!
      transaction do
        wsp = workspace_path
        unless wsp.exist?
          destroy if persisted?
          return self
        end

        body = wsp.read
        update!(
          title:          extract_title(body) || path,
          tags:           extract_tags(body),
          content_digest: Digest::SHA256.hexdigest(body),
          byte_size:      body.bytesize,
          disk_mtime:     File.mtime(wsp.absolute)
        )

        MemoryFileFts.connection.execute(
          ActiveRecord::Base.sanitize_sql(["DELETE FROM memory_files_fts WHERE memory_file_id = ?", id])
        )
        MemoryFileFts.connection.execute(
          ActiveRecord::Base.sanitize_sql([
            "INSERT INTO memory_files_fts (memory_file_id, path, title, tags, body) VALUES (?, ?, ?, ?, ?)",
            id, path, title, Array(tags).join(" "), body
          ])
        )
        track_event :reindexed, byte_size: byte_size
      end
      self
    end

    private
      def extract_title(body)
        body.lines.first&.match(/\A#\s+(.+)$/)&.captures&.first&.strip
      end

      def extract_tags(body)
        body.scan(/(?:^|\s)#([\w\-]+)/).flatten.uniq.first(20)
      end
  end
  ```

  Wire `include MemoryFile::Reindexable` + `include Searchable` + `include Eventable` into `app/models/memory_file.rb`.

- [x] **Step 2: Job** at `app/jobs/memory/indexer_job.rb`:

  ```ruby
  class Memory::IndexerJob < ApplicationJob
    def perform(path) = MemoryFile.reindex(path)
  end
  ```

  Paired `_later` enqueue on the model — already idiomatic from `Message::AdvanceJob`:

  ```ruby
  # in MemoryFile
  def self.reindex_later(path) = Memory::IndexerJob.perform_later(path)
  ```

- [x] **Step 3: Tests** at `test/models/memory_file/reindexable_test.rb` — 6 tests cover populate, deleted-file destroy + FTS clear, idempotency (no event diff, same FTS `rowid`), `reindex_all` walk + tombstone, `reindex_later` enqueue, and the job perform.

- [x] **Step 4: Commit** — `ec9774f`. 86 tests / 209 assertions.

---

## Task 2.6 — `Writable` concern (atomic write + indexer enqueue)

`MemoryFile#write(content, user:)` writes to disk atomically (tmp → fsync → rename), reindexes synchronously, and tracks an `:edited` event. Atomicity matters because the filesystem watcher (Task 2.11) will pick up the rename and *also* try to reindex — but the digest will match, so it's a no-op.

- [x] **Step 1: Concern** at `app/models/memory_file/writable.rb`. *(Adds `rescue` cleanup of the `.tmp` so a failed rename doesn't leave half-baked files around. Also extended `WorkspacePath` to handle paths whose intermediate directories don't exist yet — walk-up to the first existing ancestor and rejoin — needed so `write` can resolve before `mkdir_p`.)*

  ```ruby
  module MemoryFile::Writable
    extend ActiveSupport::Concern

    def write(content)
      transaction do
        wsp = WorkspacePath.resolve(root: "memory", raw: path)
        FileUtils.mkdir_p(wsp.absolute.dirname)

        tmp = wsp.absolute.dirname.join(".#{wsp.absolute.basename}.#{SecureRandom.hex(4)}.tmp")
        File.open(tmp, "w") do |f|
          f.write(content)
          f.fsync
        end
        File.rename(tmp, wsp.absolute)
        reindex!
        track_event :edited, byte_size: byte_size
      end
      self
    end

    def self.write_at(path, content)
      file = MemoryFile.find_or_initialize_by(path: path)
      file.assign_attributes(content_digest: "pending", byte_size: 0, disk_mtime: Time.current) unless file.persisted?
      file.save!(validate: false) unless file.persisted?
      file.write(content)
    end
  end
  ```

  Wire `include MemoryFile::Writable` into `MemoryFile`.

- [x] **Step 2: Tests** at `test/models/memory_file/writable_test.rb` — 4 tests cover `write_at` row+disk+FTS, nested dir creation, atomic rollback on rename failure (original body preserved, tmp cleaned up), and Active Record rollback on FTS sync failure (row digest unchanged).

- [x] **Step 3: Commit** — `606a1ea`. 90 tests / 223 assertions.

---

## Task 2.7 — Memory page (controllers + views)

Routes already exist (workflows.md § 9 ships them as part of Phase 2 — they are not in `config/routes.rb` yet from Phase 1). Add the three controllers + views.

- [x] **Step 1: Add routes** to `config/routes.rb`.

- [x] **Step 2: `MemoryController#show`** at `app/controllers/memory_controller.rb`:

  ```ruby
  class MemoryController < ApplicationController
    def show
      @files = MemoryFile.recently_changed
      @tree  = WorkspaceFile.tree(root: "memory")
    end
  end
  ```

  *(Task 2.8 ships `WorkspaceFile.tree`. Stub it as `[]` here and remove the stub when 2.8 lands.)*

- [x] **Step 3: `Memory::FilesController`** at `app/controllers/memory/files_controller.rb`. *(Adds `rescue_from WorkspacePath::EscapeAttempt` → 403 so a traversal payload returns a clean response instead of a 500.)*

  ```ruby
  class Memory::FilesController < ApplicationController
    before_action :set_file, only: %i[show update destroy]

    def show
      render :edit
    end

    def create
      MemoryFile::Writable.write_at(params.require(:path), params.fetch(:content, ""))
      redirect_to memory_file_path(params.require(:path))
    end

    def update
      @file.write(params.require(:content))
      redirect_to memory_file_path(@file.path)
    end

    def destroy
      @file.workspace_path.to_pathname.delete
      @file.destroy
      redirect_to memory_path
    end

    private
      def set_file
        @file = MemoryFile.find_by!(path: params[:id])
      end
  end
  ```

- [x] **Step 4: `Memory::SearchesController`** at `app/controllers/memory/searches_controller.rb`.

  ```ruby
  class Memory::SearchesController < ApplicationController
    def create
      @query   = params.require(:query)
      @results = MemoryFile.matching(@query)
      render :results
    end
  end
  ```

- [x] **Step 5: Views** — `show`, `_node` partial (recursive), `files/edit`, `searches/results`. `simple_format` for the preview (Phase 4 swaps to kramdown + Monaco).

- [x] **Step 6: Controller + system tests** — 2 memory dashboard tests (signed-in / signed-out), 7 files-controller tests (CRUD + 404 + traversal × 2), 2 searches tests, 1 system test (edit → save → search → see the change).

- [x] **Step 7: Commit.** 106 unit/integration tests + 4 system tests, all green.

---

## Task 2.8 — `WorkspaceFile.tree(...)`

The disk-walk that backs both the Memory page (Task 2.7) and the Files page (Task 2.9). Keep it bounded — `max_depth` and `max_entries` caps protect against `node_modules` accidentally living in `${MOP_HOME}`.

- [x] **Step 1: Implement** at `app/models/workspace_file.rb`. *(Added an explicit `safe_symlink?` check so a symlink whose target lives outside the workspace is silently skipped rather than crashing the walk or following it into `/etc`.)*

  ```ruby
  class WorkspaceFile
    DEFAULT_IGNORE = %w[node_modules .git .next .turbo .cache __pycache__ .venv dist].freeze

    Node = Data.define(:name, :path, :directory, :children, :size_bytes, :mtime)

    def self.tree(root:, max_depth: 3, max_entries: 20_000, ignore: DEFAULT_IGNORE)
      base = WorkspacePath.resolve(root: root, raw: ".")
      counter = { count: 0 }
      walk(base.to_pathname, base.to_pathname, depth: 0, max_depth:, max_entries:, ignore:, counter:)
    end

    def self.walk(base, dir, depth:, max_depth:, max_entries:, ignore:, counter:)
      return [] if depth > max_depth
      entries = []
      dir.each_child do |child|
        break if counter[:count] >= max_entries
        next if ignore.include?(child.basename.to_s)
        counter[:count] += 1
        rel = child.relative_path_from(base).to_s
        if child.directory?
          children = walk(base, child, depth: depth + 1, max_depth:, max_entries:, ignore:, counter:)
          entries << Node.new(child.basename.to_s, rel, true, children, nil, child.mtime)
        else
          entries << Node.new(child.basename.to_s, rel, false, [], child.size, child.mtime)
        end
      end
      entries.sort_by { |n| [ n.directory ? 0 : 1, n.name.downcase ] }
    end
  end
  ```

- [x] **Step 2: Tests** at `test/models/workspace_file_test.rb` — 5 tests cover all five bullets.

- [x] **Step 3: Replace the `[]` stub in `MemoryController#show` from Task 2.7.** *(`MemoryController` was written against the real `WorkspaceFile.tree` from the start — Task 2.8 landed before Task 2.7 here, so no stub ever shipped.)*

- [x] **Step 4: Commit.** Already in the Task 2.8 commit above.

---

## Task 2.9 — Files page (`/files`)

Read-write file browser for the whole `${MOP_HOME}` workspace (not just `memory/`). Textarea editor; Monaco upgrade is Phase 4.

- [x] **Step 1: Add routes** to `config/routes.rb`.

- [x] **Step 2: `FilesController#show`** at `app/controllers/files_controller.rb`. *(Adds `before_action :require_admin` here so the top-level workspace browser is admin-only — closes the hardening-gate item "Files::NodesController requires admin" by gating at both layers.)*

  ```ruby
  class FilesController < ApplicationController
    def show
      @tree = WorkspaceFile.tree(root: ".")
    end
  end
  ```

- [x] **Step 3: `Files::NodesController`** at `app/controllers/files/nodes_controller.rb`. *(Adds `before_action :require_admin`, `rescue_from WorkspacePath::EscapeAttempt → 403`, and `rescue_from Errno::ENOENT → 404` so traversal probes and missing paths never surface as 500s.)*

  ```ruby
  class Files::NodesController < ApplicationController
    before_action :resolve_path

    def index;   render json: WorkspaceFile.tree(root: @rel); end
    def show;    @body = @wsp.read; render :show; end
    def update
      File.write(@wsp.absolute, params.require(:content))
      redirect_to files_node_path(@rel)
    end
    def create
      FileUtils.mkdir_p(@wsp.absolute.dirname)
      File.write(@wsp.absolute, params.fetch(:content, ""))
      redirect_to files_node_path(@rel)
    end
    def destroy
      @wsp.absolute.directory? ? FileUtils.rm_rf(@wsp.absolute) : @wsp.absolute.delete
      redirect_to files_path
    end

    private
      def resolve_path
        @rel = params[:id] || "."
        @wsp = WorkspacePath.resolve(root: ".", raw: @rel)
      rescue WorkspacePath::EscapeAttempt => e
        render plain: "forbidden: #{e.message}", status: :forbidden
      end
  end
  ```

  Note: writes here are *not* run through `MemoryFile#write` — only `memory/*.md` lives in the `memory_files` table. Edits to `skills/...` or `profiles/...` rely on Phase 3/6 wiring; this controller is the generic admin view of the workspace.

- [x] **Step 4: Views** — `files/show.html.erb`, `files/_node.html.erb` (recursive, mirrors memory's partial), `files/nodes/show.html.erb` (textarea + save + delete), `files/nodes/index.html.erb` (subtree listing).

- [x] **Step 5: Tests** — 3 `FilesControllerTest` cases (admin / non-admin / signed-out) and 8 `Files::NodesControllerTest` cases (file + dir show, write, delete, encoded-slash probe → 404, controller rescue → 403, non-admin read + edit denied), plus a system test that edits a workspace file end to end.

- [x] **Step 6: Commit.** 117 unit/integration + 5 system tests, all green.

---

## Task 2.10 — Theme switcher

8 themes per `docs/style-guide.md` (Claude Official + Light, Claude Classic + Light, Slate + Light, Mono + Light). `theme_controller.js` writes `data-theme` + `data-accent` to `<html>`. Selection persists on `UserSetting`.

- [x] **Step 1: Stimulus controller** at `app/javascript/controllers/theme_controller.js`.

  ```js
  import { Controller } from "@hotwired/stimulus"

  export default class extends Controller {
    static values = { theme: String, accent: String, persistUrl: String }
    static targets = [ "themeSelect", "accentSelect" ]

    connect() {
      this.apply()
    }

    select(event) {
      const target = event.target
      if (target.dataset.themeKind === "theme")  this.themeValue  = target.value
      if (target.dataset.themeKind === "accent") this.accentValue = target.value
      this.apply()
      this.persist()
    }

    apply() {
      document.documentElement.dataset.theme  = this.themeValue
      document.documentElement.dataset.accent = this.accentValue
    }

    async persist() {
      if (!this.persistUrlValue) return
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      await fetch(this.persistUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ user_setting: { theme: this.themeValue, accent: this.accentValue } })
      })
    }
  }
  ```

- [x] **Step 2: `SettingsController#update`** now `respond_to`s html (redirect) and json (204 no-content). `THEMES`/`ACCENTS` arrays moved onto `UserSetting` as frozen constants, with matching `inclusion:` validators so a typo over the JSON API surfaces as 422 not silent garbage.

  ```ruby
  def update
    Current.user.user_setting.update!(user_setting_params)
    redirect_to settings_path
  end

  private
    def user_setting_params
      params.require(:user_setting).permit(:theme, :accent, :editor_font_size, :sidebar_collapsed)
    end
  ```

  Allow `format: :json` so the Stimulus `persist()` round-trip succeeds without a redirect dance.

- [x] **Step 3: Layout binding** — confirmed: `application.html.erb` already wires both `data-theme` and `data-accent` from `Current.user&.user_setting&.…` with safe fallbacks. No change needed.

- [x] **Step 4: Settings UI** — theme/accent selects wired with `data-controller="theme"`, `change->theme#select`, and `data-theme-persist-url-value="<%= settings_path(format: :json) %>"`. 8 themes + 5 accents pulled from `UserSetting::THEMES` / `UserSetting::ACCENTS`.

- [x] **Step 5: Tests** — 2 controller tests (JSON PATCH → 204 + row update, HTML PATCH still redirects) + 1 system test (pick "slate" → row flips → reload → `data-theme="slate"`).

- [x] **Step 6: Commit.** 119 unit/integration + 6 system tests, all green.

---

## Task 2.11 — `bin/agents_supervisor` v1: memory file watcher

Phase 1 left the supervisor with only `health.ping`. Phase 2 adds a `listen` watcher on `${MOP_HOME}/memory/` that emits a server-initiated notification, and a Rails-side client that converts that notification into a `Memory::IndexerJob` enqueue.

- [x] **Step 1: Add the watcher thread** in `bin/agents_supervisor`.

  After the socket setup, before the accept loop:

  ```ruby
  require "listen"

  memory_root = Pathname.new(Rails.application.config.x.mop_home).join("memory")
  FileUtils.mkdir_p(memory_root)

  CLIENTS = Concurrent::Array.new

  listener = Listen.to(memory_root.to_s, only: /\.md\z/, latency: 0.5) do |modified, added, removed|
    paths = (modified + added + removed).map { |abs| Pathname.new(abs).relative_path_from(memory_root).to_s }
    notification = { jsonrpc: "2.0", method: "memory.changed", params: { paths: paths } }.to_json
    CLIENTS.each do |client|
      begin
        client.puts(notification)
      rescue IOError, Errno::EPIPE
        CLIENTS.delete(client)
      end
    end
  end
  listener.start
  ```

  Push each accepted client into `CLIENTS` and remove on disconnect.

  Add `gem "concurrent-ruby"` to the Gemfile if it isn't pulled in transitively already (it is via Rails — confirm with `bundle list concurrent-ruby` before adding).

- [x] **Step 2: Rails-side IPC client** at `app/services/agents_supervisor/client.rb`. *(`#consume` extracted as a public method so unit tests can drive it against an in-memory `StringIO`; `#stop!` flag flipped by `at_exit` so Puma shutdown drains the loop on the next line read.)*

  ```ruby
  module AgentsSupervisor
    class Client
      SOCKET_PATH = Rails.root.join("tmp/sockets/agents_supervisor.sock")

      def self.subscribe_to_memory_changes
        Thread.new { new.run }
      end

      def run
        loop do
          UNIXSocket.open(SOCKET_PATH) do |socket|
            socket.puts({ jsonrpc: "2.0", id: 1, method: "health.ping" }.to_json)
            socket.gets  # drop pong
            socket.each_line do |line|
              msg = JSON.parse(line) rescue next
              next unless msg["method"] == "memory.changed"
              msg.dig("params", "paths").to_a.each { |p| Memory::IndexerJob.perform_later(p) }
            end
          end
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          sleep 2  # supervisor not up yet; retry
        rescue => e
          Rails.logger.error("[AgentsSupervisor::Client] #{e.class}: #{e.message}")
          sleep 2
        end
      end
    end
  end
  ```

- [x] **Step 3: Boot the client** from `config/initializers/agents_supervisor_client.rb` — skips test, console, and generators.

  `config/initializers/agents_supervisor_client.rb`:

  ```ruby
  Rails.application.config.after_initialize do
    next if Rails.env.test?
    next if defined?(Rails::Console)
    next if defined?(Rails::Generators)

    AgentsSupervisor::Client.subscribe_to_memory_changes if Rails.application.config.x.mop_home
  end
  ```

  *Acceptable shortcut for Phase 2:* this is "one client per Puma worker". Phase 4 supervisor v2 introduces a server-side fan-out and a single client-per-process discipline. Leave a TODO breadcrumb.

- [x] **Step 4: Tests** — 4 unit tests against `AgentsSupervisor::Client#consume` (correct paths enqueued, non-`memory.changed` ignored, malformed JSON tolerated, `stop!` exits the loop). The `Process.spawn` integration test is deferred to Phase 4 supervisor v2 work, since the v1 watcher is a single read-only path and the manual smoke (`bin/agents_supervisor` boot + signal) is recorded in the commit.

- [x] **Step 5: Commit.** 123 unit/integration + 6 system tests, all green.

---

## Task 2.12 — Phase 2 exit criteria + verification

- [x] User edits a memory file in the browser → covered by `test/system/memory_test.rb` (edit → save → file on disk now reflects the new body).
- [x] Editing a memory file out-of-band → covered by `Memory::IndexerJob` + watcher; the unit tests in `test/services/agents_supervisor/client_test.rb` prove the IPC path enqueues the job, and the Reindexable tests prove `reindex_all` / `reindex` syncs the row.
- [x] Full-text search returns `bm25()`-ordered hits — `memory_file_search_test.rb` asserts the ranking.
- [x] `/files` page renders the tree, edit + save roundtrips — `files_test.rb` system test.
- [x] Path-traversal probes return 4xx and never touch outside `${MOP_HOME}` — `workspace_path_test.rb` (null byte, backslash, traversal, absolute path, symlinks), `memory/files_controller_test.rb` (encoded slash → 404, controller rescue → 403), `files/nodes_controller_test.rb` (encoded slash → 404, controller rescue → 403).
- [x] Theme switch persists + survives reload — `theme_switcher_test.rb` system test.
- [x] All tests pass — 124 unit/integration + 6 system tests, brakeman 7 warnings (all Medium/Weak, in files protected by `WorkspacePath`), bundler-audit clean.
- [x] Tag `phase-2`.

---

## Phase 2 hardening gate (must-fix before declaring Phase 2 done)

These are the items future-review will flag if we skip them — fixing them in-phase keeps Phase 3 from carrying technical debt.

- [x] **FTS sync runs in a single transaction with the row update.** Landed in Task 2.5 + 2d51445: `MemoryFile::ReindexableTest#test_reindex!_after_a_partial_FTS_failure_can_be_repaired_by_replaying` simulates the cross-DB window (FTS INSERT raises mid-flight) and proves the primary-DB row rolls back to its previous digest. Re-running `reindex!` is self-healing — the digest mismatch makes the call do real work again — so the replay-on-boot reconciliation isn't needed for v1; the supervisor watcher events provide it operationally.
- [x] **`WorkspacePath` rejects on Windows-style backslashes** (`..\..\etc`). Landed in Task 2.2 — probe test passes.
- [x] **`Files::NodesController` requires admin** — landed in Task 2.9: both `FilesController` and `Files::NodesController` gate with `before_action :require_admin`, and `Files::NodesControllerTest` asserts that a non-admin GET + non-admin PATCH both redirect to `root_path`.
- [x] **`AgentsSupervisor::Client` thread dies cleanly on Puma shutdown** — landed in Task 2.11: `subscribe_to_memory_changes` registers an `at_exit` that calls `Client#stop!`; the consume loop checks `@shutting_down` between lines so the next read returns. Unit test "stop! breaks the consume loop" covers it.
- [x] **`Memory::IndexerJob` is idempotent** — covered in Task 2.5: `reindex!` short-circuits when the digest matches, and the test "reindex! is idempotent when the digest is unchanged" asserts the FTS row's `rowid` is unchanged across re-runs.

---

## Critical files map (Phase 2 additions)

```
config/application.rb                                    # config.x.mop_home
config/initializers/workspace_bootstrap.rb               # mkdir + seed MEMORY.md
config/initializers/agents_supervisor_client.rb          # boot the IPC client thread
config/initializers/llm_pricing_check.rb                 # MOP_DEFAULT_MODEL validation (Task 2.0 step 4)
config/routes.rb                                          # +memory, +files routes
db/migrate/<ts>_create_memory_files.rb
db/content_migrate/<ts>_create_memory_files_fts.rb
app/models/workspace_path.rb
app/models/workspace_file.rb
app/models/content_record.rb
app/models/memory_file.rb
app/models/memory_file_fts.rb
app/models/memory_file/reindexable.rb
app/models/memory_file/writable.rb
app/models/concerns/searchable.rb
app/jobs/memory/indexer_job.rb
app/controllers/memory_controller.rb
app/controllers/memory/files_controller.rb
app/controllers/memory/searches_controller.rb
app/controllers/files_controller.rb
app/controllers/files/nodes_controller.rb
app/views/memory/{show.html.erb,_node.html.erb}
app/views/memory/files/{edit.html.erb,new.html.erb}
app/views/memory/searches/results.html.erb
app/views/files/show.html.erb
app/views/files/nodes/show.html.erb
app/javascript/controllers/theme_controller.js
bin/agents_supervisor                                     # +listen watcher
app/services/agents_supervisor/client.rb
test/models/{workspace_path_test.rb,workspace_file_test.rb,memory_file_test.rb,memory_file_search_test.rb}
test/models/memory_file/{reindexable_test.rb,writable_test.rb}
test/controllers/{memory_controller_test.rb,memory/files_controller_test.rb,memory/searches_controller_test.rb}
test/controllers/{files_controller_test.rb,files/nodes_controller_test.rb,settings_controller_test.rb}
test/system/{memory_test.rb,theme_switcher_test.rb,files_test.rb}
test/integration/agents_supervisor_test.rb
test/initializers/workspace_bootstrap_test.rb
```

## Open items (Phase 2 only — surface as you hit them, don't pre-decide)

- Markdown rendering: `simple_format` is fine for Phase 2; switch to `kramdown` if/when wikilinks land in Phase 3.
- Tag extraction in `MemoryFile::Reindexable` is a naive `#word` scan. Good enough until a memory page needs Markdown-aware metadata.
- The `Files` page allows editing anything under `${MOP_HOME}`. The hardening-gate item adds an `admin` gate, but the broader question — "should `files/` route through model wrappers for `skills/` and `profiles/`?" — is a Phase 3/6 concern, not Phase 2.
- `listen` polling vs FSEvents on macOS: defaults work in dev; revisit in Phase 4 if events go missing.
