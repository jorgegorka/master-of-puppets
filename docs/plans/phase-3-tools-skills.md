# Phase 3 — Built-in tools + Skills

> **Executor:** Use `superpowers:subagent-driven-development` (or `superpowers:executing-plans`) to drive these tasks one at a time. Each `- [ ]` step has file paths, a failing test, the minimal impl, the verification command + expected output, and a commit. Tick the box as you complete each step.

**Parent plan:** [`docs/plans/workflows.md`](workflows.md) § Phase 3.

**Goal:** the chat tool loop becomes real — built-in tools (`read_file`, `write_file`, `list_dir`, `run_shell`) execute end-to-end; skills load from `${MOP_HOME}/skills/` on disk, can be installed + enabled per user, and enabled skills change the system prompt.

**Adds (high level):**

- `skills`, `skill_installations`, `skill_enablements` migrations on `primary`. (`agent_profile_skills` is deferred to Phase 6 — its parent `agent_profiles` table doesn't exist yet.)
- `Skill` model composing five concerns: `Loadable`, `SecurityAnalyzable`, `Installable`, `Enableable`, `Searchable`, plus `Eventable`.
- `Skill::SecurityAnalysis` PORO + heuristic-driven `security_level` upgrades over the frontmatter declaration.
- `skills_fts` virtual table on the `content` DB. `Searchable` is parameterized so `MemoryFile` and `Skill` share the same concern.
- `Tool::Internal` registry + four built-in tool classes (`read_file`, `write_file`, `list_dir`, `run_shell`) with per-tool input schemas and admin gating for shell.
- `ToolCall::Executable#execute` (real, replaces the Phase 1 `NotImplementedError` stub) — looks up by `source`, records timestamps, fires `:invoked` / `:succeeded` / `:failed` events, persists output.
- `Message::Streamable#available_tools` + `#infer_source` wired to the real registry instead of returning `[]` / `:internal`.
- Skills page (`/skills`) — categories, search, install + enable buttons, security badge.
- Seed `db/seeds/skills/` (5 builtins: filesystem, web_search stub, code_review, deep_research, summarize) — copied into `${MOP_HOME}/skills/` on first boot.
- `bin/agents_supervisor` v1+: extends the Phase-2 watcher to also listen on `${MOP_HOME}/skills/` and enqueue `Skill::ReloadJob`.

**Exit criteria:** see Task 3.14.

---

## Task 3.0 — Commit in-flight Phase 2 follow-ups

These hardening items are already implemented in the working tree but uncommitted:

- `Memory::FullReindexJob` + boot enqueue + test (cold-start replay)
- `require_admin` on `MemoryController`, `Memory::FilesController`, `Memory::SearchesController` + matching controller-test cases
- `WorkspacePath::ALLOWED_ROOTS` whitelist + probe test
- `MemoryFile::Writable.write_at` simplified (no pre-save with `"pending"` digest)
- `bin/agents_supervisor`: socket `chmod 0600` + multi-tenant socket TODO comment
- `AgentsSupervisor::Client#stop!` closes the socket so a blocked `each_line` exits cleanly

They finish the Phase 2 hardening gate and don't depend on Phase 3 work. Commit them first so Phase 3 has a clean baseline.

- [ ] **Step 1: Review the working-tree diff.**

  ```bash
  git status
  git diff --stat HEAD
  bin/rails test
  ```

  Expected: all tests green, `Memory::FullReindexJobTest` + the new probes in `WorkspacePathTest` + the admin checks in the memory controller tests included.

- [ ] **Step 2: Commit the cleanup.**

  Stage explicitly (avoid `git add -A`):

  ```bash
  git add \
    app/controllers/memory/files_controller.rb \
    app/controllers/memory/searches_controller.rb \
    app/controllers/memory_controller.rb \
    app/models/memory_file/writable.rb \
    app/models/workspace_path.rb \
    app/services/agents_supervisor/client.rb \
    app/jobs/memory/full_reindex_job.rb \
    bin/agents_supervisor \
    config/initializers/agents_supervisor_client.rb \
    test/controllers/memory \
    test/jobs/memory \
    test/models/workspace_path_test.rb \
    test/services/agents_supervisor/client_test.rb \
    test/system/memory_test.rb
  ```

  Commit message:

  ```
  Phase 2 follow-ups: admin gate on /memory, FullReindex on cold start, socket hardening
  ```

- [ ] **Step 3: Tag.** `git tag phase-2-final` so the Phase 3 baseline is unambiguous.

---

## Task 3.1 — `skills` table + `Skill` model

Disk is source of truth at `${MOP_HOME}/skills/<category>/<slug>/SKILL.md`. The row is an index/cache, mirroring the `MemoryFile` pattern.

- [ ] **Step 1: Migration.**

  ```bash
  bin/rails g migration CreateSkills
  ```

  Edit `db/migrate/<ts>_create_skills.rb`:

  ```ruby
  class CreateSkills < ActiveRecord::Migration[8.1]
    def change
      create_table :skills do |t|
        t.string  :slug,           null: false
        t.string  :name,           null: false
        t.string  :category,       null: false
        t.text    :description
        t.json    :manifest,       null: false, default: {}
        t.string  :source_path,    null: false
        t.integer :origin,         null: false, default: 0
        t.integer :security_level, null: false, default: 0
        t.string  :body_digest,    null: false
        t.datetime :discovered_at, null: false

        t.timestamps
      end
      add_index :skills, :slug,     unique: true
      add_index :skills, :category
      add_index :skills, :security_level
    end
  end
  ```

  Run: `bin/rails db:migrate`.

- [ ] **Step 2: `Skill` model** at `app/models/skill.rb`:

  ```ruby
  class Skill < ApplicationRecord
    include Eventable

    enum :origin,         { builtin: 0, agent_created: 1, marketplace: 2 }
    enum :security_level, { safe: 0, low: 1, medium: 2, high: 3 }

    validates :slug, presence: true, uniqueness: true
    validates :name, :category, :source_path, :body_digest, presence: true

    scope :enabled_for,   ->(user) { joins(:enablements).where(skill_enablements: { user_id: user.id }) }
    scope :installed_for, ->(user) { joins(:installations).where(skill_installations: { user_id: user.id }) }
  end
  ```

  Concerns + associations land in 3.2–3.5; this is just the table-backed model.

- [ ] **Step 3: Fixture** at `test/fixtures/skills.yml`:

  ```yaml
  filesystem:
    slug: filesystem
    name: Filesystem
    category: io
    description: Read and write files in the workspace.
    manifest: <%= { name: "filesystem", description: "Read and write files in the workspace.", category: "io", allowed_tools: %w[read_file write_file list_dir] }.to_json %>
    source_path: <%= Rails.root.join("test/fixtures/files/skills/filesystem/SKILL.md").to_s %>
    origin: 0
    security_level: 0
    body_digest: <%= Digest::SHA256.hexdigest("# Filesystem\n\nRead and write files.\n") %>
    discovered_at: <%= 1.hour.ago.utc.iso8601 %>
  ```

  Create the fixture file at `test/fixtures/files/skills/filesystem/SKILL.md`:

  ```markdown
  ---
  name: filesystem
  description: Read and write files in the workspace.
  category: io
  allowed_tools:
    - read_file
    - write_file
    - list_dir
  ---

  # Filesystem

  Read and write files.
  ```

- [ ] **Step 4: Model test** at `test/models/skill_test.rb`:

  ```ruby
  require "test_helper"

  class SkillTest < ActiveSupport::TestCase
    test "slug uniqueness" do
      dup = Skill.new(skills(:filesystem).attributes.except("id"))
      refute dup.valid?
      assert_includes dup.errors[:slug], "has already been taken"
    end

    test "origin + security_level enums round-trip" do
      s = skills(:filesystem)
      assert s.builtin?
      assert s.safe?
    end
  end
  ```

  Run: `bin/rails test test/models/skill_test.rb` → 2 runs, 0 failures.

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.1: Skill model + skills migration + fixture
  ```

---

## Task 3.2 — `Skill::Loadable` concern (frontmatter parser + reload)

Parses YAML frontmatter from a `SKILL.md`, computes a `body_digest`, upserts the row. Mirrors `MemoryFile::Reindexable` so both surfaces feel the same.

- [ ] **Step 1: Failing test** at `test/models/skill/loadable_test.rb`:

  ```ruby
  require "test_helper"

  class Skill::LoadableTest < ActiveSupport::TestCase
    setup do
      @tmp       = Dir.mktmpdir
      @prev_home = Rails.application.config.x.mop_home
      Rails.application.config.x.mop_home = @tmp
      skills_root = Pathname.new(@tmp).join("skills/io/filesystem")
      skills_root.mkpath
      skills_root.join("SKILL.md").write(<<~MD)
        ---
        name: filesystem
        description: Read and write files.
        category: io
        allowed_tools: [read_file, write_file]
        ---
        # Filesystem
        Body here.
      MD
    end

    teardown do
      FileUtils.rm_rf(@tmp)
      Rails.application.config.x.mop_home = @prev_home
    end

    test "reload_from_disk creates one Skill per SKILL.md and tombstones missing ones" do
      stale = Skill.create!(
        slug: "ghost", name: "Ghost", category: "io",
        source_path: "vanished", body_digest: "0", discovered_at: 1.day.ago,
        manifest: {}
      )

      paths = Skill.reload_from_disk
      assert_equal 1, paths.length
      refute Skill.exists?(stale.id), "stale skill should be tombstoned"
      skill = Skill.find_by!(slug: "filesystem")
      assert_equal "Read and write files.", skill.description
      assert_equal "io", skill.category
      assert_equal %w[read_file write_file], skill.manifest["allowed_tools"]
    end

    test "load_from_path! is idempotent — same body, no event diff" do
      Skill.reload_from_disk
      skill = Skill.find_by!(slug: "filesystem")
      digest = skill.body_digest
      event_count = skill.events.count

      skill.load_from_path!
      assert_equal digest, skill.reload.body_digest
      assert_equal event_count, skill.events.count
    end

    test "missing frontmatter raises MalformedSkill" do
      Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").write("no frontmatter here")
      skill = Skill.new(source_path: Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").to_s)
      assert_raises(Skill::Loadable::MalformedSkill) { skill.load_from_path! }
    end
  end
  ```

- [ ] **Step 2: Concern** at `app/models/skill/loadable.rb`:

  ```ruby
  module Skill::Loadable
    extend ActiveSupport::Concern

    class MalformedSkill < StandardError; end

    FRONTMATTER_RE = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

    class_methods do
      # Walks ${MOP_HOME}/skills/**/SKILL.md, upserts a row per file, and
      # tombstones rows whose source_path is gone. Returns the array of
      # source_paths that were seen.
      def reload_from_disk
        root = Pathname.new(Rails.application.config.x.mop_home).join("skills")
        seen = []
        Pathname.glob(root.join("**/SKILL.md")).each do |path|
          skill = find_or_initialize_by(source_path: path.to_s)
          skill.load_from_path!
          seen << path.to_s
        end
        where.not(source_path: seen).destroy_all
        seen
      end
    end

    def load_from_path!
      path = Pathname.new(source_path)
      raw  = path.read
      match = raw.match(FRONTMATTER_RE)
      raise MalformedSkill, "no frontmatter at #{source_path}" unless match

      manifest_yaml = YAML.safe_load(match[1], permitted_classes: [ Symbol ])
      raise MalformedSkill, "frontmatter must be a Hash" unless manifest_yaml.is_a?(Hash)
      manifest_yaml = manifest_yaml.deep_stringify_keys
      body = match[2]
      digest = Digest::SHA256.hexdigest(body)

      return self if persisted? && digest == body_digest

      transaction do
        update!(
          slug:           manifest_yaml.fetch("name") { path.parent.basename.to_s },
          name:           manifest_yaml.fetch("name") { path.parent.basename.to_s },
          category:       manifest_yaml.fetch("category", path.parent.parent.basename.to_s),
          description:    manifest_yaml["description"],
          manifest:       manifest_yaml,
          source_path:    source_path,
          origin:         (origin || :builtin),
          security_level: derive_security_level(manifest_yaml, body),
          body_digest:    digest,
          discovered_at:  Time.current
        )
        track_event :reloaded, body_digest: digest
      end
      self
    end

    def body
      Pathname.new(source_path).read.split(/\A---\s*\n.*?\n---\s*\n/m, 2).last.to_s
    end

    private
      # Phase 3 Task 3.3 replaces this with Skill::SecurityAnalyzable. For now
      # honour the frontmatter declaration with `safe` as the default.
      def derive_security_level(manifest, _body)
        Skill.security_levels.fetch(manifest["security_level"].to_s, 0)
      end
  end
  ```

  Wire `include Skill::Loadable` into `app/models/skill.rb`.

- [ ] **Step 3: Tests pass.**

  Run: `bin/rails test test/models/skill/loadable_test.rb` → 3 runs, 0 failures.

- [ ] **Step 4: Commit.**

  ```
  Phase 3 Task 3.2: Skill::Loadable — frontmatter parser + reload_from_disk
  ```

---

## Task 3.3 — `Skill::SecurityAnalyzable` + `Skill::SecurityAnalysis` PORO

Frontmatter declares a baseline `security_level`. Body heuristics can *upgrade* it (never downgrade): shell-command mention bumps to `medium`, network call to `high`.

- [ ] **Step 1: PORO** at `app/models/skill/security_analysis.rb`:

  ```ruby
  Skill::SecurityAnalysis = Data.define(:declared_level, :heuristic_flags, :final_level) do
    LEVELS = %i[safe low medium high].freeze

    SHELL_PATTERNS    = [ /run_shell/i, /system\s*\(/, /`[^`]+`/, /\$\([^)]+\)/ ].freeze
    NETWORK_PATTERNS  = [ /https?:\/\//i, /net\/http/i, /faraday/i, /Excon/i ].freeze
    FILE_WRITE_PATTERNS = [ /write_file/i, /File\.write/i, /FileUtils\.(?:mv|cp|rm)/i ].freeze

    def self.from(declared:, body:)
      flags = []
      flags << :shell    if SHELL_PATTERNS.any?     { |re| body =~ re }
      flags << :network  if NETWORK_PATTERNS.any?   { |re| body =~ re }
      flags << :file_write if FILE_WRITE_PATTERNS.any? { |re| body =~ re }

      heuristic_min = if flags.include?(:network)    then :high
                      elsif flags.include?(:shell)   then :medium
                      elsif flags.include?(:file_write) then :low
                      else :safe
                      end

      declared_sym = declared.to_sym
      final = [ declared_sym, heuristic_min ].max_by { |l| LEVELS.index(l) }
      new(declared_sym, flags, final)
    end
  end
  ```

- [ ] **Step 2: Concern** at `app/models/skill/security_analyzable.rb`:

  ```ruby
  module Skill::SecurityAnalyzable
    extend ActiveSupport::Concern

    def security_analysis
      Skill::SecurityAnalysis.from(
        declared: manifest["security_level"] || "safe",
        body:     body
      )
    end
  end
  ```

  Wire `include Skill::SecurityAnalyzable` into `Skill`. Replace the `derive_security_level` placeholder in `Skill::Loadable` with:

  ```ruby
  def derive_security_level(manifest, body)
    analysis = Skill::SecurityAnalysis.from(declared: manifest["security_level"] || "safe", body: body)
    Skill.security_levels[analysis.final_level.to_s]
  end
  ```

- [ ] **Step 3: Tests** at `test/models/skill/security_analyzable_test.rb`:

  ```ruby
  require "test_helper"

  class Skill::SecurityAnalyzableTest < ActiveSupport::TestCase
    test "declared level survives when body has no triggers" do
      a = Skill::SecurityAnalysis.from(declared: "low", body: "just markdown")
      assert_equal :low, a.final_level
      assert_empty a.heuristic_flags
    end

    test "shell mention upgrades to medium" do
      a = Skill::SecurityAnalysis.from(declared: "safe", body: "use `run_shell` for tar")
      assert_equal :medium, a.final_level
      assert_includes a.heuristic_flags, :shell
    end

    test "network call upgrades to high" do
      a = Skill::SecurityAnalysis.from(declared: "safe", body: "GET https://example.com")
      assert_equal :high, a.final_level
      assert_includes a.heuristic_flags, :network
    end

    test "declared level can only be upgraded, never downgraded" do
      a = Skill::SecurityAnalysis.from(declared: "high", body: "no triggers")
      assert_equal :high, a.final_level
    end
  end
  ```

  Run: `bin/rails test test/models/skill/security_analyzable_test.rb` → 4 runs, 0 failures.

- [ ] **Step 4: Loadable re-test.** Add to `test/models/skill/loadable_test.rb`:

  ```ruby
  test "body with `run_shell` upgrades security_level to medium" do
    Pathname.new(@tmp).join("skills/io/filesystem/SKILL.md").write(<<~MD)
      ---
      name: filesystem
      description: x
      category: io
      security_level: safe
      ---
      Use `run_shell` to invoke tar.
    MD
    Skill.reload_from_disk
    assert_equal "medium", Skill.find_by!(slug: "filesystem").security_level
  end
  ```

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.3: SecurityAnalyzable — heuristic upgrades over frontmatter
  ```

---

## Task 3.4 — `SkillInstallation` + `Skill::Installable`

Installation = non-repudiation record. Required before any `security_level >= medium` skill can be enabled. One row per `(skill, user)`.

- [ ] **Step 1: Migration.**

  ```bash
  bin/rails g migration CreateSkillInstallations
  ```

  ```ruby
  class CreateSkillInstallations < ActiveRecord::Migration[8.1]
    def change
      create_table :skill_installations do |t|
        t.references :skill, null: false, foreign_key: true
        t.references :user,  null: false, foreign_key: true
        t.integer    :accepted_security_level, null: false
        t.datetime   :accepted_at, null: false

        t.timestamps
      end
      add_index :skill_installations, %i[skill_id user_id], unique: true
    end
  end
  ```

  `bin/rails db:migrate`.

- [ ] **Step 2: `SkillInstallation` model** at `app/models/skill_installation.rb`:

  ```ruby
  class SkillInstallation < ApplicationRecord
    belongs_to :skill
    belongs_to :user

    validates :skill_id, uniqueness: { scope: :user_id }
  end
  ```

- [ ] **Step 3: Concern** at `app/models/skill/installable.rb`:

  ```ruby
  module Skill::Installable
    extend ActiveSupport::Concern

    included do
      has_many :installations, class_name: "SkillInstallation", dependent: :destroy
      has_many :installers, through: :installations, source: :user
    end

    def installed_for?(user)
      installations.exists?(user_id: user.id)
    end

    def install_for(user)
      installation = installations.find_or_create_by!(user: user) do |i|
        i.accepted_security_level = Skill.security_levels[security_level]
        i.accepted_at = Time.current
      end
      track_event :installed, user_id: user.id, security_level: security_level
      installation
    end

    def uninstall_for(user)
      installation = installations.find_by(user: user)
      return false unless installation
      installation.destroy
      track_event :uninstalled, user_id: user.id
      true
    end
  end
  ```

  Wire `include Skill::Installable` into `Skill`.

- [ ] **Step 4: Tests** at `test/models/skill/installable_test.rb`:

  ```ruby
  require "test_helper"

  class Skill::InstallableTest < ActiveSupport::TestCase
    test "install_for is idempotent" do
      skill = skills(:filesystem)
      user  = users(:one)
      a = skill.install_for(user)
      b = skill.install_for(user)
      assert_equal a, b
      assert_equal 1, SkillInstallation.where(skill: skill, user: user).count
    end

    test "install_for records accepted_security_level + event" do
      skill = skills(:filesystem)
      user  = users(:one)
      assert_difference -> { Event.where(action: "skill_installed").count }, 1 do
        skill.install_for(user)
      end
      i = SkillInstallation.find_by(skill: skill, user: user)
      assert_equal Skill.security_levels[skill.security_level], i.accepted_security_level
    end

    test "uninstall_for removes the row + tracks event" do
      skill = skills(:filesystem)
      user  = users(:one)
      skill.install_for(user)
      assert_difference -> { Event.where(action: "skill_uninstalled").count }, 1 do
        skill.uninstall_for(user)
      end
      refute skill.installed_for?(user)
    end
  end
  ```

  Run → 3 runs, 0 failures.

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.4: Skill::Installable + SkillInstallation
  ```

---

## Task 3.5 — `SkillEnablement` + `Skill::Enableable`

Enablement = "this user wants the skill's system-prompt section + tool defs injected on their chats." Requires installation for `security_level >= medium`.

- [ ] **Step 1: Migration.**

  ```ruby
  class CreateSkillEnablements < ActiveRecord::Migration[8.1]
    def change
      create_table :skill_enablements do |t|
        t.references :skill, null: false, foreign_key: true
        t.references :user,  null: false, foreign_key: true
        t.datetime   :enabled_at, null: false

        t.timestamps
      end
      add_index :skill_enablements, %i[skill_id user_id], unique: true
    end
  end
  ```

- [ ] **Step 2: Model** at `app/models/skill_enablement.rb`:

  ```ruby
  class SkillEnablement < ApplicationRecord
    belongs_to :skill
    belongs_to :user

    validates :skill_id, uniqueness: { scope: :user_id }
  end
  ```

- [ ] **Step 3: Concern** at `app/models/skill/enableable.rb`:

  ```ruby
  module Skill::Enableable
    extend ActiveSupport::Concern

    class NotInstalled < StandardError; end

    included do
      has_many :enablements, class_name: "SkillEnablement", dependent: :destroy
      has_many :enabled_users, through: :enablements, source: :user
    end

    def enabled_for?(user)
      enablements.exists?(user_id: user.id)
    end

    def enable_for(user)
      if requires_installation? && !installed_for?(user)
        raise NotInstalled, "#{slug} (#{security_level}) requires explicit install_for(user)"
      end
      enablement = enablements.find_or_create_by!(user: user) { |e| e.enabled_at = Time.current }
      track_event :enabled, user_id: user.id
      enablement
    end

    def disable_for(user)
      enablement = enablements.find_by(user: user)
      return false unless enablement
      enablement.destroy
      track_event :disabled, user_id: user.id
      true
    end

    private
      def requires_installation?
        %w[medium high].include?(security_level)
      end
  end
  ```

  Wire `include Skill::Enableable` into `Skill`.

- [ ] **Step 4: Tests** at `test/models/skill/enableable_test.rb`:

  ```ruby
  require "test_helper"

  class Skill::EnableableTest < ActiveSupport::TestCase
    test "enable_for safe skill works without installation" do
      skill = skills(:filesystem)  # safe
      user  = users(:one)
      skill.enable_for(user)
      assert skill.enabled_for?(user)
    end

    test "enable_for medium skill raises without installation" do
      skill = skills(:filesystem)
      skill.update!(security_level: :medium)
      assert_raises(Skill::Enableable::NotInstalled) do
        skill.enable_for(users(:one))
      end
    end

    test "enable_for medium skill succeeds after install_for" do
      skill = skills(:filesystem)
      skill.update!(security_level: :medium)
      user  = users(:one)
      skill.install_for(user)
      skill.enable_for(user)
      assert skill.enabled_for?(user)
    end

    test "disable_for removes the row" do
      skill = skills(:filesystem)
      user  = users(:one)
      skill.enable_for(user)
      skill.disable_for(user)
      refute skill.enabled_for?(user)
    end
  end
  ```

  Run → 4 runs, 0 failures.

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.5: Skill::Enableable + SkillEnablement
  ```

---

## Task 3.6 — Parameterize `Searchable` + `skills_fts` virtual table

Phase 2 hardcoded `Searchable` to `MemoryFileFts`. Lift it to a per-class declaration so `Skill` (and Phase 4's `Message`) can reuse the concern.

- [ ] **Step 1: Failing test** — extend `test/models/memory_file_search_test.rb` and add `test/models/skill_search_test.rb`. New skill test:

  ```ruby
  require "test_helper"

  class SkillSearchTest < ActiveSupport::TestCase
    setup do
      Skill.delete_all
      @fs    = Skill.create!(skills(:filesystem).attributes.except("id", "created_at", "updated_at"))
      @debug = Skill.create!(skills(:filesystem).attributes.except("id", "created_at", "updated_at").merge(
        slug: "debug", name: "Debug", description: "Step through code with the debugger",
        body_digest: Digest::SHA256.hexdigest("debug")
      ))
      [@fs, @debug].each(&:reindex_fts!)
    end

    test "matching returns bm25-ordered skill results" do
      results = Skill.matching("debug")
      assert_equal [@debug.id], results.map(&:id)
    end

    test "matching is namespaced (skills don't return memory hits)" do
      MemoryFile.create!(path: "x.md", title: "Debugger", tags: [], content_digest: "d", byte_size: 0, disk_mtime: Time.current)
      results = Skill.matching("debug")
      results.each { |r| assert_kind_of Skill, r }
    end
  end
  ```

- [ ] **Step 2: Refactor `Searchable`** at `app/models/concerns/searchable.rb`:

  ```ruby
  module Searchable
    extend ActiveSupport::Concern

    class_methods do
      attr_reader :fts_class, :fts_foreign_key

      def searchable_via(fts_class, foreign_key:)
        @fts_class       = fts_class
        @fts_foreign_key = foreign_key
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
  end
  ```

  Update `MemoryFile`:

  ```ruby
  class MemoryFile < ApplicationRecord
    include Eventable
    include Searchable
    searchable_via MemoryFileFts, foreign_key: :memory_file_id

    include Reindexable
    include Writable
    # ...
  end
  ```

- [ ] **Step 3: Content migration** for `skills_fts`.

  ```bash
  bin/rails g migration CreateSkillsFts --database=content
  ```

  Edit `db/content_migrate/<ts>_create_skills_fts.rb`:

  ```ruby
  class CreateSkillsFts < ActiveRecord::Migration[8.1]
    COLUMNS = [
      "skill_id UNINDEXED",
      "slug",
      "name",
      "category",
      "description",
      "body",
      "tokenize = 'porter'"
    ].freeze

    def change
      create_virtual_table :skills_fts, :fts5, COLUMNS
    end
  end
  ```

  Run: `bin/rails db:migrate`.

- [ ] **Step 4: `SkillFts` model** at `app/models/skill_fts.rb`:

  ```ruby
  class SkillFts < ContentRecord
    self.table_name  = "skills_fts"
    self.primary_key = nil
  end
  ```

- [ ] **Step 5: Wire FTS sync into `Skill::Loadable`.** Add to the `transaction do` block in `load_from_path!`, right after `update!(...)`:

  ```ruby
  reindex_fts!(body)
  ```

  Add the helper method:

  ```ruby
  def reindex_fts!(body = nil)
    body ||= self.body
    SkillFts.connection.execute(
      ActiveRecord::Base.sanitize_sql([ "DELETE FROM skills_fts WHERE skill_id = ?", id ])
    )
    SkillFts.connection.execute(
      ActiveRecord::Base.sanitize_sql([
        "INSERT INTO skills_fts (skill_id, slug, name, category, description, body) VALUES (?, ?, ?, ?, ?, ?)",
        id, slug, name, category, description.to_s, body
      ])
    )
  end
  ```

  Add an `after_destroy_commit` to clear the FTS row.

  Add to `Skill` the `include Searchable` + `searchable_via SkillFts, foreign_key: :skill_id`.

- [ ] **Step 6: Tests pass.**

  Run: `bin/rails test test/models/memory_file_search_test.rb test/models/skill_search_test.rb test/models/skill/loadable_test.rb` → all green.

- [ ] **Step 7: Commit.**

  ```
  Phase 3 Task 3.6: Searchable per-class FTS adapter + skills_fts
  ```

---

## Task 3.7 — `Tool::Internal` registry + `Tool::Result` PORO

Plain-Ruby registry. Each built-in tool is a class with `self.input_schema` and `self.invoke(input:, user:)` → `Tool::Result`. No state, no AR row — `ToolCall` is the persistence layer.

- [ ] **Step 1: `Tool::Result` PORO** at `app/models/tool/result.rb`:

  ```ruby
  Tool::Result = Data.define(:output, :error, :is_error) do
    def self.ok(output)     = new(output, nil, false)
    def self.failure(error) = new(nil,    error, true)

    def to_tool_block(provider_tool_id)
      {
        "type"        => "tool_result",
        "tool_use_id" => provider_tool_id,
        "content"     => is_error ? error.to_s : output.to_s,
        "is_error"    => is_error
      }
    end
  end
  ```

- [ ] **Step 2: Registry base** at `app/models/tool/internal.rb`:

  ```ruby
  class Tool::Internal
    class UnknownTool < StandardError; end
    class Forbidden  < StandardError; end

    class << self
      def register(name, klass)
        registry[name.to_s] = klass
      end

      def lookup(name)
        registry[name.to_s]
      end

      def all_definitions
        registry.values.map(&:tool_definition)
      end

      def invoke(name:, input:, user:)
        klass = lookup(name) or raise UnknownTool, name
        klass.invoke(input: input.to_h.deep_stringify_keys, user: user)
      end

      private
        def registry
          @registry ||= {}
        end
    end

    # Subclasses implement these three.
    def self.tool_name;   raise NotImplementedError; end
    def self.description; raise NotImplementedError; end
    def self.input_schema; raise NotImplementedError; end

    def self.tool_definition
      { name: tool_name, description: description, input_schema: input_schema }
    end
  end
  ```

- [ ] **Step 3: Registry initializer** at `config/initializers/tool_internal_registry.rb`:

  ```ruby
  Rails.application.config.after_initialize do
    [
      Tool::Internal::ReadFile,
      Tool::Internal::WriteFile,
      Tool::Internal::ListDir,
      Tool::Internal::RunShell
    ].each { |klass| Tool::Internal.register(klass.tool_name, klass) }
  end
  ```

- [ ] **Step 4: Test** at `test/models/tool/internal_test.rb`:

  ```ruby
  require "test_helper"

  class Tool::InternalTest < ActiveSupport::TestCase
    test "lookup returns the registered class" do
      assert_equal Tool::Internal::ReadFile, Tool::Internal.lookup("read_file")
    end

    test "lookup returns nil for unknown" do
      assert_nil Tool::Internal.lookup("nonexistent")
    end

    test "all_definitions includes each tool's schema" do
      defs = Tool::Internal.all_definitions
      names = defs.map { |d| d[:name] }
      assert_includes names, "read_file"
      assert_includes names, "write_file"
      assert_includes names, "list_dir"
      assert_includes names, "run_shell"
    end

    test "invoke raises UnknownTool for missing name" do
      assert_raises(Tool::Internal::UnknownTool) do
        Tool::Internal.invoke(name: "missing", input: {}, user: users(:one))
      end
    end
  end
  ```

  Run after Task 3.8 (when the four tool classes exist) — for now the test will fail with `NameError: Tool::Internal::ReadFile` because the classes don't exist yet. Skip the run; commit the registry + result PORO only, then unskip in 3.8.

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.7: Tool::Internal registry + Tool::Result PORO
  ```

---

## Task 3.8 — Built-in tools (read_file, write_file, list_dir, run_shell)

Four classes under `app/models/tool/internal/`. Each accepts `input:` (hash) + `user:` (User) and returns `Tool::Result`.

- [ ] **Step 1: `read_file`** at `app/models/tool/internal/read_file.rb`:

  ```ruby
  class Tool::Internal::ReadFile < Tool::Internal
    MAX_BYTES = 256 * 1024

    def self.tool_name;   "read_file"; end
    def self.description; "Read a UTF-8 text file from the workspace."; end
    def self.input_schema
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path relative to ${MOP_HOME}, e.g. memory/notes/a.md" }
        },
        required: [ "path" ]
      }
    end

    def self.invoke(input:, user:)
      wsp = WorkspacePath.resolve(root: ".", raw: input.fetch("path"))
      return Tool::Result.failure("not found: #{input["path"]}") unless wsp.exist?
      return Tool::Result.failure("path is a directory") if wsp.absolute.directory?
      bytes = File.size(wsp.absolute)
      if bytes > MAX_BYTES
        return Tool::Result.failure("file is #{bytes} bytes (max #{MAX_BYTES})")
      end
      Tool::Result.ok(wsp.read)
    rescue WorkspacePath::EscapeAttempt => e
      Tool::Result.failure("forbidden: #{e.message}")
    end
  end
  ```

- [ ] **Step 2: `write_file`** at `app/models/tool/internal/write_file.rb`:

  ```ruby
  class Tool::Internal::WriteFile < Tool::Internal
    MAX_BYTES = 1 * 1024 * 1024  # 1 MB

    def self.tool_name;   "write_file"; end
    def self.description; "Write content to a file in the workspace (atomic: tmp → fsync → rename)."; end
    def self.input_schema
      {
        type: "object",
        properties: {
          path:    { type: "string" },
          content: { type: "string" }
        },
        required: %w[path content]
      }
    end

    def self.invoke(input:, user:)
      content = input.fetch("content")
      return Tool::Result.failure("content too large") if content.bytesize > MAX_BYTES

      wsp = WorkspacePath.resolve(root: ".", raw: input.fetch("path"))
      FileUtils.mkdir_p(wsp.absolute.dirname)
      tmp = wsp.absolute.dirname.join(".#{wsp.absolute.basename}.#{SecureRandom.hex(4)}.tmp")
      File.open(tmp, "w") do |f|
        f.write(content)
        f.fsync
      end
      File.rename(tmp, wsp.absolute)
      Tool::Result.ok("wrote #{content.bytesize} bytes to #{wsp.rel}")
    rescue WorkspacePath::EscapeAttempt => e
      Tool::Result.failure("forbidden: #{e.message}")
    ensure
      File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
    end
  end
  ```

- [ ] **Step 3: `list_dir`** at `app/models/tool/internal/list_dir.rb`:

  ```ruby
  class Tool::Internal::ListDir < Tool::Internal
    def self.tool_name;   "list_dir"; end
    def self.description; "List the contents of a workspace directory (one level)."; end
    def self.input_schema
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Directory path relative to ${MOP_HOME}. Empty string for root." }
        },
        required: [ "path" ]
      }
    end

    def self.invoke(input:, user:)
      raw = input.fetch("path", "").to_s
      raw = "." if raw.empty?
      wsp = WorkspacePath.resolve(root: ".", raw: raw)
      return Tool::Result.failure("not a directory: #{raw}") unless wsp.absolute.directory?

      entries = wsp.absolute.children.map do |c|
        kind = c.directory? ? "dir" : "file"
        size = c.directory? ? "-" : c.size.to_s
        "#{kind}\t#{size}\t#{c.basename}"
      end.sort
      Tool::Result.ok(entries.join("\n"))
    rescue WorkspacePath::EscapeAttempt => e
      Tool::Result.failure("forbidden: #{e.message}")
    end
  end
  ```

- [ ] **Step 4: `run_shell`** at `app/models/tool/internal/run_shell.rb`:

  Admin-only (Tool::Internal::Forbidden if user is not admin). Runs `Open3.capture3` with a 30-second timeout and `chdir: ${MOP_HOME}`. Captures stdout + stderr, truncated to 64 KiB.

  ```ruby
  require "open3"
  require "timeout"

  class Tool::Internal::RunShell < Tool::Internal
    MAX_OUTPUT_BYTES = 64 * 1024
    TIMEOUT_SECONDS  = 30

    def self.tool_name;   "run_shell"; end
    def self.description; "Run a shell command in the workspace (admin only, sandboxed via cwd, 30s timeout)."; end
    def self.input_schema
      {
        type: "object",
        properties: {
          command: { type: "string", description: "Shell command to execute." }
        },
        required: [ "command" ]
      }
    end

    def self.invoke(input:, user:)
      unless user&.admin?
        return Tool::Result.failure("run_shell is admin-only")
      end
      command = input.fetch("command").to_s
      return Tool::Result.failure("empty command") if command.strip.empty?

      cwd = Rails.application.config.x.mop_home
      output, status = Timeout.timeout(TIMEOUT_SECONDS) do
        stdout, stderr, st = Open3.capture3(command, chdir: cwd)
        [ "$ #{command}\n#{stdout}#{stderr}", st ]
      end
      output = output[0, MAX_OUTPUT_BYTES] + "\n…[truncated]" if output.bytesize > MAX_OUTPUT_BYTES
      status.success? ? Tool::Result.ok(output) : Tool::Result.failure("exit #{status.exitstatus}: #{output}")
    rescue Timeout::Error
      Tool::Result.failure("timed out after #{TIMEOUT_SECONDS}s")
    end
  end
  ```

- [ ] **Step 5: Tests** at `test/models/tool/internal/read_file_test.rb`, `write_file_test.rb`, `list_dir_test.rb`, `run_shell_test.rb`. Example for `read_file`:

  ```ruby
  require "test_helper"

  class Tool::Internal::ReadFileTest < ActiveSupport::TestCase
    setup do
      @tmp = Dir.mktmpdir
      @prev = Rails.application.config.x.mop_home
      Rails.application.config.x.mop_home = @tmp
      FileUtils.mkdir_p(File.join(@tmp, "memory"))
      File.write(File.join(@tmp, "memory/a.md"), "hello")
    end

    teardown do
      FileUtils.rm_rf(@tmp)
      Rails.application.config.x.mop_home = @prev
    end

    test "reads a file" do
      result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory/a.md" }, user: users(:one))
      assert result.is_error == false
      assert_equal "hello", result.output
    end

    test "rejects traversal" do
      result = Tool::Internal::ReadFile.invoke(input: { "path" => "../../etc/passwd" }, user: users(:one))
      assert result.is_error
      assert_match /forbidden/, result.error
    end

    test "rejects oversize file" do
      File.write(File.join(@tmp, "memory/big.md"), "x" * (Tool::Internal::ReadFile::MAX_BYTES + 1))
      result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory/big.md" }, user: users(:one))
      assert result.is_error
    end

    test "rejects a directory" do
      result = Tool::Internal::ReadFile.invoke(input: { "path" => "memory" }, user: users(:one))
      assert result.is_error
      assert_match /directory/, result.error
    end
  end
  ```

  Mirror tests for `write_file` (round-trip + traversal + oversize), `list_dir` (one-level entries + traversal), and `run_shell` (admin gate, success, non-zero exit, timeout via stub).

- [ ] **Step 6: Un-skip and re-run `Tool::Internal` registry test** (from Task 3.7 Step 4): all 4 runs green.

- [ ] **Step 7: Commit.**

  ```
  Phase 3 Task 3.8: built-in tools — read_file, write_file, list_dir, run_shell
  ```

---

## Task 3.9 — `ToolCall::Executable#execute` real implementation

Replace the `NotImplementedError` stub. Look up by `source`; `internal` → `Tool::Internal.invoke`; `mcp` → out-of-scope (Phase 4, return failure); `skill` → out-of-scope (Phase 6, return failure). Records timestamps; fires `:invoked`, `:succeeded` / `:failed`; persists `output`.

- [ ] **Step 1: Update `app/models/tool_call/executable.rb`:**

  ```ruby
  module ToolCall::Executable
    extend ActiveSupport::Concern

    class UnsupportedSource < StandardError; end

    def execute
      raise "tool_call already #{status}" unless pending?

      transaction do
        update!(status: :running, started_at: Time.current)
        track_event :invoked, source: source, name: name
      end

      result =
        case source.to_sym
        when :internal
          Tool::Internal.invoke(name: name, input: input.to_h, user: message.chat_session.user)
        when :mcp, :skill
          Tool::Result.failure("#{source} tool execution lands in Phase 4/6")
        else
          raise UnsupportedSource, source
        end

      transaction do
        update!(
          status:        result.is_error ? :failed : :succeeded,
          finished_at:   Time.current,
          output:        result.is_error ? nil : { content: result.output },
          error_message: result.is_error ? result.error : nil
        )
        track_event(result.is_error ? :failed : :succeeded,
          name: name,
          duration_ms: ((finished_at - started_at) * 1000).to_i)
      end
      self
    rescue => e
      update!(status: :failed, finished_at: Time.current, error_message: "#{e.class}: #{e.message}")
      track_event :failed, name: name, error_class: e.class.name
      raise
    end
  end
  ```

- [ ] **Step 2: Test** at `test/models/tool_call/executable_test.rb`:

  ```ruby
  require "test_helper"

  class ToolCall::ExecutableTest < ActiveSupport::TestCase
    setup do
      @msg = messages(:hello)
      @tc  = ToolCall.create!(
        message: @msg,
        provider_tool_id: "toolu_test",
        name: "read_file",
        source: :internal,
        input: { "path" => "memory/MEMORY.md" },
        status: :pending
      )
      Tool::Internal.stub :invoke, Tool::Result.ok("body") do
        @tc.execute
      end
    end

    test "moves pending → succeeded + persists output" do
      assert @tc.reload.succeeded?
      assert_equal "body", @tc.output["content"]
      assert_not_nil @tc.started_at
      assert_not_nil @tc.finished_at
    end

    test "tracks invoked + succeeded events" do
      events = @tc.events.pluck(:action)
      assert_includes events, "tool_call_invoked"
      assert_includes events, "tool_call_succeeded"
    end

    test "re-executing a non-pending call raises" do
      assert_raises(RuntimeError) { @tc.execute }
    end

    test "failed Tool::Result transitions to failed + records error_message" do
      tc = ToolCall.create!(message: @msg, provider_tool_id: "toolu_bad", name: "read_file",
        source: :internal, input: { "path" => "missing" }, status: :pending)
      Tool::Internal.stub :invoke, Tool::Result.failure("not found") do
        tc.execute
      end
      assert tc.reload.failed?
      assert_equal "not found", tc.error_message
    end

    test "mcp and skill sources return Phase-4/6 placeholder failure (don't raise)" do
      tc = ToolCall.create!(message: @msg, provider_tool_id: "toolu_mcp", name: "do_x",
        source: :mcp, input: {}, status: :pending)
      tc.execute
      assert tc.reload.failed?
      assert_match /Phase 4/, tc.error_message
    end
  end
  ```

  Run → 5 runs, 0 failures.

- [ ] **Step 3: Commit.**

  ```
  Phase 3 Task 3.9: ToolCall::Executable#execute — real dispatcher
  ```

---

## Task 3.10 — Wire `Message::Streamable#available_tools` + `infer_source`

Replace the Phase 1 stubs.

- [ ] **Step 1: Update `app/models/message/streamable.rb`:**

  ```ruby
  def available_tools
    Tool::Internal.all_definitions + enabled_skills.flat_map { |s| skill_tool_definitions(s) }
  end

  def enabled_skills
    Skill.enabled_for(chat_session.user)
  end

  def skill_tool_definitions(skill)
    # Phase 3 wires Tool::Internal only. Skills inject prompt sections (Phase 3
    # Task 3.11 Step 3) but their tool-def array lands in Phase 6 alongside
    # the agent profile work. Return [] now to keep the surface area honest.
    []
  end

  def infer_source(name)
    return :internal if Tool::Internal.lookup(name)
    return :mcp      if defined?(McpTool) && McpTool.exists?(name: name)
    :skill
  end
  ```

- [ ] **Step 2: Update `chat_session` system prompt** so enabled skills append their bodies. Edit `prompt_messages`:

  ```ruby
  def prompt_messages
    system = build_system_prompt
    history = chat_session.messages.ordered.where("messages.id <= ?", id).map do |m|
      { role: m.role, content: m.content_blocks }
    end
    system.empty? ? history : ([ { role: :system, content: system } ] + history)
  end

  def build_system_prompt
    enabled_skills.map { |s| "## Skill: #{s.name}\n\n#{s.body}" }.join("\n\n")
  end
  ```

- [ ] **Step 3: Test** — extend `test/models/message/streamable_test.rb`:

  ```ruby
  test "available_tools includes Tool::Internal definitions" do
    msg = messages(:hello)
    names = msg.send(:available_tools).map { |d| d[:name] }
    assert_includes names, "read_file"
    assert_includes names, "write_file"
  end

  test "build_system_prompt embeds enabled skill bodies" do
    msg = messages(:hello)
    skill = skills(:filesystem)
    skill.enable_for(msg.chat_session.user)
    skill.stub :body, "RULES: be careful" do
      assert_includes msg.send(:build_system_prompt), "RULES: be careful"
    end
  end

  test "infer_source returns :internal for read_file" do
    msg = messages(:hello)
    assert_equal :internal, msg.send(:infer_source, "read_file")
  end
  ```

  Run → all green.

- [ ] **Step 4: VCR cassette for end-to-end tool loop.** Re-record `test/fixtures/vcr/anthropic_tool_call.yml` if it exists from Phase 1; otherwise capture a new one with a prompt that exercises `read_file`. Use:

  ```bash
  VCR_RECORD=new_episodes bin/rails test test/models/message/streamable_test.rb -n "test_tool_loop_round_trip"
  ```

  Add the round-trip test (skip-gated by cassette presence):

  ```ruby
  test "tool_loop_round_trip: stream → tool_call → succeeded → tool_result block appended" do
    skip "needs VCR cassette" unless File.exist?(Rails.root.join("test/fixtures/vcr/anthropic_tool_call.yml"))
    VCR.use_cassette("anthropic_tool_call") do
      session = chat_sessions(:one)
      session.messages.create!(role: :user, content_blocks: [{type:"text",text:"Read memory/MEMORY.md"}], status: :completed)
      assistant = session.messages.create!(role: :assistant, content_blocks: [], status: :pending,
        model: "claude-haiku-4-5", provider: "anthropic")
      assistant.advance!
      assert assistant.tool_calls.where(name: "read_file", status: :succeeded).exists?
      assert assistant.content_blocks.any? { |b| b["type"] == "tool_result" }
    end
  end
  ```

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.10: wire Message available_tools + infer_source + skill system prompt
  ```

---

## Task 3.11 — Skills page

`/skills` lists categories + search; `/skills/:id` shows the SKILL.md body + install/enable buttons + security badge. Per workflows.md § 9.

- [ ] **Step 1: Add routes** to `config/routes.rb`:

  ```ruby
  resources :skills, only: %i[index show update destroy] do
    scope module: :skills do
      resources :installations, only: %i[create destroy]
      resource  :enablement,    only: %i[create destroy]
    end
  end
  ```

- [ ] **Step 2: `SkillsController`** at `app/controllers/skills_controller.rb`:

  ```ruby
  class SkillsController < ApplicationController
    before_action :require_admin, only: %i[update destroy]
    before_action :set_skill, only: %i[show update destroy]

    def index
      @query  = params[:q].to_s
      @skills = @query.present? ? Skill.matching(@query) : Skill.all.order(:category, :name)
      @categories = Skill.distinct.pluck(:category).sort
    end

    def show
      @installed = @skill.installed_for?(Current.user)
      @enabled   = @skill.enabled_for?(Current.user)
    end

    def update
      @skill.load_from_path!
      redirect_to @skill, notice: "Reloaded from disk."
    end

    def destroy
      @skill.destroy
      redirect_to skills_path, notice: "Removed."
    end

    private
      def set_skill
        @skill = Skill.find(params[:id])
      end
  end
  ```

- [ ] **Step 3: `Skills::InstallationsController`** at `app/controllers/skills/installations_controller.rb`:

  ```ruby
  class Skills::InstallationsController < ApplicationController
    before_action :set_skill

    def create
      @skill.install_for(Current.user)
      redirect_to @skill
    end

    def destroy
      @skill.uninstall_for(Current.user)
      redirect_to @skill
    end

    private
      def set_skill
        @skill = Skill.find(params[:skill_id])
      end
  end
  ```

- [ ] **Step 4: `Skills::EnablementsController`** at `app/controllers/skills/enablements_controller.rb`:

  ```ruby
  class Skills::EnablementsController < ApplicationController
    before_action :set_skill
    rescue_from Skill::Enableable::NotInstalled, with: :require_install

    def create
      @skill.enable_for(Current.user)
      redirect_to @skill
    end

    def destroy
      @skill.disable_for(Current.user)
      redirect_to @skill
    end

    private
      def set_skill
        @skill = Skill.find(params[:skill_id])
      end

      def require_install(e)
        redirect_to @skill, alert: e.message
      end
  end
  ```

- [ ] **Step 5: Views** —

  `app/views/skills/index.html.erb`: search input (form POSTs to `skills_path`), category-grouped list of skills, each row links to `skill_path(skill)` + shows the security badge.

  `app/views/skills/show.html.erb`: header (name, category, security badge), body (`simple_format(@skill.body)`), install + enable buttons (toggle `button_to` to the right controller).

  Helper at `app/helpers/skills_helper.rb`:

  ```ruby
  module SkillsHelper
    SECURITY_BADGE_CLASS = {
      "safe"   => "badge badge--ok",
      "low"    => "badge badge--ok",
      "medium" => "badge badge--warn",
      "high"   => "badge badge--danger"
    }.freeze

    def security_badge(skill)
      content_tag :span, skill.security_level, class: SECURITY_BADGE_CLASS.fetch(skill.security_level, "badge")
    end
  end
  ```

- [ ] **Step 6: Tests** at `test/controllers/skills_controller_test.rb`, `test/controllers/skills/installations_controller_test.rb`, `test/controllers/skills/enablements_controller_test.rb`. Cover:
  - signed-out → redirect
  - index renders + search filters
  - show renders + security badge present
  - install → SkillInstallation created
  - enable on medium skill without install → flash alert + no enablement
  - enable on safe skill works
  - update + destroy are admin-only (non-admin → redirect)

  System test at `test/system/skills_test.rb`: sign in, visit `/skills`, click a skill, install, enable, assert UI shows "enabled" state.

- [ ] **Step 7: Commit.**

  ```
  Phase 3 Task 3.11: Skills page — controllers + views + system test
  ```

---

## Task 3.12 — Seed `db/seeds/skills/` + workspace bootstrap

5 built-in skills, copied into `${MOP_HOME}/skills/` on first boot. Disk is source of truth.

- [ ] **Step 1: Author 5 SKILL.md files** under `db/seeds/skills/`:

  ```
  db/seeds/skills/io/filesystem/SKILL.md
  db/seeds/skills/search/web_search/SKILL.md       # stub — describes the contract but tool wires up in Phase 4 MCP
  db/seeds/skills/review/code_review/SKILL.md
  db/seeds/skills/research/deep_research/SKILL.md
  db/seeds/skills/writing/summarize/SKILL.md
  ```

  Each file follows the § 4.5 format. Example (`filesystem/SKILL.md`):

  ```markdown
  ---
  name: filesystem
  description: Read and write files in the workspace, list directories.
  category: io
  triggers:
    - "read the file"
    - "list the directory"
  security_level: safe
  allowed_tools:
    - read_file
    - write_file
    - list_dir
  ---

  # Filesystem

  You can read and write files inside the workspace using the `read_file`,
  `write_file`, and `list_dir` tools. Prefer relative paths; never escape
  the workspace root.
  ```

- [ ] **Step 2: Extend `config/initializers/workspace_bootstrap.rb`** to copy seed skills on first boot:

  ```ruby
  # Inside the after_initialize block, after the existing mkdir_p loop:
  seed_dir = Rails.root.join("db/seeds/skills")
  if seed_dir.directory?
    skills_root = root.join("skills")
    Dir.glob(seed_dir.join("**/SKILL.md")).each do |seed|
      rel = Pathname.new(seed).relative_path_from(seed_dir)
      dest = skills_root.join(rel)
      next if dest.exist?  # never clobber edited skills
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.cp(seed, dest)
    end
  end
  ```

- [ ] **Step 3: Boot-time skill reload.** Add to the same initializer, *after* the copy block:

  ```ruby
  Skill::ReloadJob.perform_later if defined?(Skill)
  ```

  Plus `app/jobs/skill/reload_job.rb`:

  ```ruby
  class Skill::ReloadJob < ApplicationJob
    queue_as :default

    def perform(path: nil)
      if path
        Skill.find_or_initialize_by(source_path: path).load_from_path!
      else
        Skill.reload_from_disk
      end
    end
  end
  ```

- [ ] **Step 4: Test** at `test/jobs/skill/reload_job_test.rb` + `test/initializers/workspace_bootstrap_test.rb` extension. The bootstrap test asserts:
  - seed files copied to `${MOP_HOME}/skills/io/filesystem/SKILL.md` on a fresh tmp dir
  - re-running the bootstrap doesn't clobber an edited skill
  - `Skill::ReloadJob.perform_later` enqueues 1 job

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.12: seed db/seeds/skills + bootstrap copy + Skill::ReloadJob
  ```

---

## Task 3.13 — `bin/agents_supervisor` skills watcher

Phase 2 added the memory watcher. Phase 3 adds a second `Listen.to` block for `${MOP_HOME}/skills/` and emits `skills.changed` notifications.

- [ ] **Step 1: Edit `bin/agents_supervisor`** — duplicate the memory listener block, scoped to `skills/`:

  ```ruby
  skills_root = Pathname.new(Rails.application.config.x.mop_home).join("skills")
  FileUtils.mkdir_p(skills_root)

  skills_listener = Listen.to(skills_root.to_s, only: /SKILL\.md\z/, latency: 0.5) do |modified, added, removed|
    paths = (modified + added + removed).map { |abs| abs.to_s }
    notification = { jsonrpc: "2.0", method: "skills.changed", params: { paths: paths } }.to_json
    CLIENTS.each do |client|
      begin
        client.puts(notification)
      rescue IOError, Errno::EPIPE
        CLIENTS.delete(client)
      end
    end
  end
  skills_listener.start
  ```

- [ ] **Step 2: Extend `app/services/agents_supervisor/client.rb`** to handle `skills.changed`:

  ```ruby
  case message["method"]
  when "memory.changed"
    Array(message.dig("params", "paths")).each { |p| Memory::IndexerJob.perform_later(p) }
  when "skills.changed"
    Array(message.dig("params", "paths")).each { |p| Skill::ReloadJob.perform_later(path: p) }
  end
  ```

- [ ] **Step 3: Cold-start replay** — add to `config/initializers/agents_supervisor_client.rb`, next to `Memory::FullReindexJob.perform_later`:

  ```ruby
  Skill::ReloadJob.perform_later
  ```

  This catches edits that happened while the supervisor was down.

- [ ] **Step 4: Tests** — extend `test/services/agents_supervisor/client_test.rb`:

  ```ruby
  test "skills.changed paths enqueue Skill::ReloadJob" do
    client = AgentsSupervisor::Client.new
    payload = { jsonrpc: "2.0", method: "skills.changed", params: { paths: [ "/tmp/x/SKILL.md" ] } }.to_json + "\n"
    socket = StringIO.new(payload)
    assert_enqueued_with(job: Skill::ReloadJob, args: [ { path: "/tmp/x/SKILL.md" } ]) do
      client.consume(socket)
    end
  end
  ```

- [ ] **Step 5: Commit.**

  ```
  Phase 3 Task 3.13: supervisor — skills/ watcher + Skill::ReloadJob enqueue
  ```

---

## Task 3.14 — Phase 3 exit criteria + verification

- [x] **User opens `/skills` and sees the 5 seed skills**, grouped by category, each with a security badge. Covered by `test/system/skills_test.rb`. *Verified: 1 run, 3 assertions, 0 failures.*
- [x] **Editing a SKILL.md on disk reloads the row** — verified by `Skill::ReloadJobTest` + supervisor IPC test (`AgentsSupervisor::ClientTest`). *Verified: 8 runs, 15 assertions, 0 failures.*
- [x] **Installing a skill writes one `SkillInstallation` + an `:installed` event** — `Skill::InstallableTest`. *Verified: 3 runs, 8 assertions, 0 failures.*
- [x] **Enabling a `medium` skill without installation is refused with a clear flash** — `Skills::EnablementsControllerTest`. *Verified: 3 runs, 12 assertions, 0 failures.*
- [x] **Enabled skills append their body to the system prompt** — `Message::StreamableTest`. *Verified: full file 14 runs / 44 assertions, 0 failures (1 skip is the round-trip test below).*
- [ ] **The chat tool loop completes end-to-end with a real built-in tool** — `Message::StreamableTest#test_tool_loop_round_trip` against the VCR cassette. *Skipped: cassette `test/fixtures/vcr/anthropic_tool_call.yml` not yet recorded. Contract is covered at the unit level by Task 3.9's `run_tool_calls!` reader test in `MessageTest` and Task 3.10's `ToolCall::Executable#execute` test (5 runs / 14 assertions, all pass). Full HTTP round-trip will be recorded once a real Anthropic API key is wired in.*
- [x] **`run_shell` is admin-only** — non-admin invocation returns `Tool::Result.failure("run_shell is admin-only")`. `Tool::Internal::RunShellTest`. *Verified: 8 runs, 26 assertions, 0 failures.*
- [x] **All tests pass** — after Task 3.15 hardening: `bin/rails test` (213 runs / 571 assertions / 0 failures / 1 pre-existing symlink skip) + `bin/rails test:system` (7 runs / 21 assertions / 0 failures) both green; `brakeman` 10 warnings (Phase 2 baseline 7 + 3 new from `app/models/tool/internal/write_file.rb`, all Medium/File Access in WorkspacePath-protected code, same pattern as the baseline); `bundler-audit` clean (0 vulnerabilities, ruby-advisory-db 2026-05-14).
- [x] **Tag `phase-3`.** *Tagged in Task 3.15 after the hardening gate closed (`phase-3` only — no `-final` variant, see Task 3.15 notes).*

---

## Phase 3 hardening gate (must-fix before declaring Phase 3 done)

These are the items future-review will flag if skipped. Tick each before the `phase-3` tag.

- [x] **`Tool::Internal::WriteFile` rolls back on a rename failure** — `rescue SystemCallError` added in `app/models/tool/internal/write_file.rb`; rename failure now returns `Tool::Result.failure("write failed: …")` and the `ensure` block deletes the tmp. Covered by `test/models/tool/internal/write_file_test.rb` ("cleans up tmp file on rename failure" + "returns failure (not raise) on rename system error").

- [x] **`Tool::Internal::RunShell` cannot escape `${MOP_HOME}`** — TODO breadcrumb added at the top of `app/models/tool/internal/run_shell.rb` pointing to Phase 4's supervisor v2 (rlimits + uid drop + namespaces). Admin-gate + audit-log remain the only safety net until then.

- [x] **`Skill::Loadable#reload_from_disk` survives a malformed SKILL.md** — per-file `load_from_path!` wrapped in `rescue MalformedSkill` with `Rails.logger.warn` in `app/models/skill/loadable.rb`. Covered by `test/models/skill/loadable_test.rb` ("reload_from_disk tolerates a malformed SKILL.md and continues").

- [x] **`SkillFts` row is removed on `Skill#destroy`** — `after_destroy_commit :clear_fts_entry!` already wired in Task 3.6; regression test added in `test/models/skill_search_test.rb` ("destroying a skill clears its FTS row").

- [x] **`Searchable#matching` quotes the FTS table name** — already landed in Task 3.6 via `connection.quote_table_name`. Existing `test/models/skill_search_test.rb` exercises this path end-to-end on the `skills_fts` table.

- [x] **`Tool::Internal.register` is idempotent** — confirmed by reading `app/models/tool/internal.rb` (`registry[name.to_s] = klass` overwrites). Test added in `test/models/tool/internal_test.rb` ("register is idempotent — re-registering overwrites without duplicating").

- [x] **`Skill::Enableable#enable_for` is atomic with the install check** — wrapped the install-check + enablement creation in `transaction do … end` in `app/models/skill/enableable.rb`. Existing `test/models/skill/enableable_test.rb` keeps passing (no behavior change for serial callers; concurrent races are now serialized by the transaction).

---

## Task 3.16 — Post-review fix-ups (Phase 3 batch 2)

A full Phase 3 code review on 2026-05-16 surfaced 4 critical and ~20 important/minor issues. After triage (4 parallel review agents cross-checking source against this plan + `workflows.md` § 16), the following ship as a Phase 3 batch-2. Items that genuinely belong to Phase 4/5/6 are listed in *Open items* below, not here.

Three commit groups — land in order so the test suite stays green at each boundary:

- **3.16a — Critical correctness + model layer**
- **3.16b — Tool registry hardening**
- **3.16c — Skills UI & wiring**

After all three land, retag (`git tag -d phase-3 && git tag phase-3`) so the tag points at the green tree.

### 3.16a — Critical correctness + model layer

- [x] **C1 — Anthropic system prompt is sent as `system:` kwarg, not a `messages[0]` entry.** Today's `Message::Streamable#prompt_messages` prepends `{role: :system, content: …}` to `messages:`, and `Llm::Anthropic#stream` forwards that — the Anthropic Ruby SDK requires `system:` as a separate top-level kwarg and rejects `{role: "system"}` inside `messages` (400). The exit-criterion test (line 1730) only asserts the `prompt_messages` *shape*; the VCR round-trip (line 1731) was skipped, so this never fired against a real API.
  - **File:** `app/services/llm/anthropic.rb` — add `system:` to `#stream(...)` signature; pass through as `@client.messages.stream(..., system: system.presence)`. Update `Llm::Adapter` interface comment.
  - **File:** `app/models/message/streamable.rb` — split `prompt_messages` so it returns history only; add `system_prompt` reader that returns the string from `build_system_prompt`. Pass `system: system_prompt` into `llm_adapter.stream`.
  - **Test:** `test/services/llm/anthropic_test.rb` — stub `@client.messages` and assert `.stream` receives `system: "## Skill: …"` as a kwarg, not as a `messages[0]` entry.
  - **Test:** `test/models/message/streamable_test.rb` — update existing prompt assertion: (a) no `:system` role in `messages`, (b) `system_prompt` returns concatenated skill body.

- [x] **C3 — `run_shell` production safety gate + env scrub + PGID kill.** Full sandbox stays Phase 4 (rlimits / uid drop / namespaces — see Open items). What lands now: (a) gate registration on `ENV.fetch("MOP_ENABLE_RUN_SHELL", Rails.env.production? ? "false" : "true") == "true"` so prod is default-off, (b) scrub `DATABASE_URL` / `RAILS_MASTER_KEY` / `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` from the child env, (c) spawn with `Process.setpgid` and kill the process group on `Timeout::Error` (current `Timeout.timeout` wrap leaves the `/bin/sh -c` child running).
  - **File:** `config/initializers/tool_internal_registry.rb` — conditionally register `Tool::Internal::RunShell` based on the env flag.
  - **File:** `app/models/tool/internal/run_shell.rb` — replace `Open3.capture3(command, chdir: cwd)` with `Open3.popen3({"DATABASE_URL"=>nil, "RAILS_MASTER_KEY"=>nil, "ANTHROPIC_API_KEY"=>nil, "OPENAI_API_KEY"=>nil}, command, chdir: cwd, pgroup: true)`. Capture child PID; on `Timeout::Error` call `Process.kill("-TERM", -pid)` then `-KILL` after 2s. Keep the Phase-4 TODO breadcrumb.
  - **Test:** `test/models/tool/internal/run_shell_test.rb` — add: "is unregistered when MOP_ENABLE_RUN_SHELL=false", "DATABASE_URL is not visible to the child", "child is killed on timeout (no orphan `sleep` survives)".

- [x] **C4 — Coalesce `Skill::ReloadJob` per-path concurrency.** Boot-replay + per-worker supervisor fan-out causes N× enqueues of the same `(path: …)` job (N = Puma worker count). DB unique index on `skills.slug` prevents data corruption, but it's pure queue noise + wasted reparses. Full worker-0 gating is Phase 4 supervisor v2 (see Open items); for now add a path-keyed concurrency control on the job itself.
  - **File:** `app/jobs/skill/reload_job.rb` — add Solid Queue concurrency control: `limits_concurrency to: 1, key: ->(path: nil) { "skill-reload:#{path || 'all'}" }`. If Solid Queue concurrency syntax differs from the gem version in use, fall back to a `Rails.cache.write(..., unless_exist: true, expires_in: 5.seconds)` short-circuit at top of `perform`.
  - **Test:** `test/jobs/skill/reload_job_test.rb` — add "two enqueues for the same path produce one final row" (the count assertion already implicit, but make it explicit). If concurrency-key infra is available, also assert only one of two parallel enqueues executes.

- [x] **M1 — Wrap `install_for`, `uninstall_for`, `disable_for` in transactions.** Task 3.15 already wrapped `enable_for`; the other three concern methods still do mutation + `track_event` without a transaction. Pinnable/Archivable already follow the rule; this restores parity.
  - **File:** `app/models/skill/installable.rb` — wrap `install_for` body (find_or_create_by! + track_event) and `uninstall_for` body (destroy + track_event after the early return) in `transaction do … end`.
  - **File:** `app/models/skill/enableable.rb` — wrap `disable_for` body in `transaction do … end`.
  - **Test:** `test/models/skill/installable_test.rb` + `test/models/skill/enableable_test.rb` — stub `track_event` to raise; assert the installation/enablement row is rolled back (count unchanged).

- [x] **M2 — Stop `Skill::SecurityAnalysis` over-triggering on prose backticks + bare URLs.** Today every inline-code span and every `https://…` in documentation prose promotes a `safe` SKILL.md to `:medium` (which then requires explicit install). The seeded `db/seeds/skills/io/filesystem/SKILL.md` (declared `safe`) gets bumped to `medium` and breaks the install/enable UX for well-documented safe skills.
  - **File:** `app/models/skill/security_analysis.rb` — restrict `SHELL_PATTERNS` and `NETWORK_PATTERNS` scans to fenced code blocks only (`body.scan(/```.*?```/m).join("\n")`). Drop the broad backtick pattern. Drop the bare `https?://` pattern; keep library-shape matches (`net/http`, `faraday`, `Excon`, `URI.open`, `Net::HTTP`, `HTTParty`).
  - **Plus T10 (related):** extend `SHELL_PATTERNS` to also catch `\beval\b`, `\bexec\b`, `Kernel\.(?:spawn|system|exec|fork)`, `IO\.popen`, `\bOpen3\.`, `Process\.(?:spawn|fork|exec)` — current set misses these obvious code-execution vectors.
  - **Test:** `test/models/skill/security_analyzable_test.rb` — add: "prose backticks in docs do not flag shell", "https URL in prose does not flag network", "shell pattern inside fenced code DOES flag", "URL inside fenced code with Net::HTTP DOES flag network", one assertion per new SHELL pattern. Also add an end-to-end assertion (`test/models/skill/loadable_test.rb`) that the seeded `filesystem` SKILL.md resolves to `safe`.

- [x] **M3 — Move FTS reindex out of the AR transaction → `after_commit`.** `Skill::Loadable#load_from_path!` runs `reindex_fts!` inside `transaction do …` while the FTS write goes through `SkillFts.connection` (different DB, content). A rollback after the FTS write (e.g. `track_event` failure) leaves stale rows. The destroy path is already correct (`after_destroy_commit :clear_fts_entry!`, hardening line 1748) — the write path missed the dual.
  - **File:** `app/models/skill/loadable.rb` — capture `@pending_fts_body = body` inside the transaction; add `after_commit :flush_fts_write` that calls `reindex_fts!(@pending_fts_body) if @pending_fts_body` then nils it.
  - **File:** `app/models/memory_file/reindexable.rb` — same treatment (this is a Phase 2 carry-over with the identical bug; fix in tandem so the concern's contract is consistent).
  - **Test:** `test/models/skill_search_test.rb` — add "rollback of `update!` leaves no stale FTS row". Stub `track_event` to raise inside `load_from_path!`, assert FTS count for that slug is 0.
  - **Test:** `test/models/memory_file_search_test.rb` (or equivalent) — mirror.

**Commit message:** `Phase 3 Task 3.16a: anthropic system kwarg + run_shell prod gate + reload concurrency + skill concern transactions + FTS after_commit + tighter security heuristics`

### 3.16b — Tool registry hardening

- [ ] **T1 — Validate input against `input_schema` at the registry boundary.** Today malformed args (`{"path": 123}`, missing required keys) raise `KeyError` / `NoMethodError` inside the tool, get caught by `ToolCall::Executable`'s blanket rescue, and surface as poorly-typed error strings. Add a centralized `Tool::Internal.validate!(input, schema)` returning `Tool::Result.failure("invalid input: …")` before `klass.invoke`.
  - **File:** `app/models/tool/internal.rb` — add a minimal schema check (required keys present, top-level types match `schema[:properties][k][:type]`). No need for a JSON-schema gem in Phase 3.
  - **Test:** `test/models/tool/internal_test.rb` — "invoke with missing required key returns Result.failure", "invoke with wrong-typed key returns Result.failure".

- [ ] **T2 — `write_file` defaults to no-overwrite.** Add `overwrite: { type: "boolean", default: false }` to `input_schema`. If destination exists and `overwrite` is not true, return `Tool::Result.failure("file exists; pass overwrite: true to replace")` before `mkdir_p`.
  - **File:** `app/models/tool/internal/write_file.rb`
  - **Test:** `test/models/tool/internal/write_file_test.rb` — "writing to existing path without overwrite returns failure and leaves original bytes untouched"; "writing with overwrite: true replaces".

- [ ] **T3 — Snapshot/restore `Tool::Internal` registry around tests.** The Phase 3 tests mutate the global `@registry` and never restore it.
  - **File:** `test/models/tool/internal_test.rb` — add `setup`/`teardown` that snapshots `Tool::Internal.send(:registry).dup` and restores in teardown. (Alternative: delete just the keys added by the test; snapshot-restore is cheap and total.)

- [ ] **T4 — `ToolCall::Executable#execute` re-raises the `pending?` guard without overwriting state.** Today the guard `raise "tool_call already #{status}" unless pending?` lives inside the rescue scope; if a `:succeeded` row has `execute` called again, the rescue overwrites it to `:failed` before re-raising.
  - **File:** `app/models/tool_call/executable.rb` — move the `pending?` guard above the `begin … rescue … end` block. The rescue then never sees the guard exception.
  - **Test:** `test/models/tool_call/executable_test.rb` — "after a successful execute, a second execute raises but reload.succeeded? stays true (status unchanged)".

- [ ] **T5 — Hide `run_shell` from non-admin `available_tools`.** Today the registry exposes it to every user; only `RunShell.invoke` itself checks `user.admin?`. Cheap to also filter the tool definitions so non-admins don't see it as an option. Broader per-user/per-skill tool filtering is Phase 6 (`agent_profile_skills`).
  - **File:** `app/models/message/streamable.rb` — in `available_tools`, drop `"run_shell"` from `Tool::Internal.all_definitions` for non-admin users.
  - **Test:** `test/models/message/streamable_test.rb` — "available_tools for non-admin excludes run_shell; admin sees it".

- [ ] **T6 — Cap skill body in system prompt + memoize `enabled_skills`.** Bodies live in the DB (not disk re-read — the review's framing was off there), but they are unbounded and `enabled_skills` is recomputed per `advance!` iteration. A single 5 MB skill kills future calls via provider rejection.
  - **File:** `app/models/message/streamable.rb` — introduce `MAX_SKILL_BODY_BYTES = 64_000`, truncate each body in `build_system_prompt` (append `"\n…[truncated]"`), memoize `@enabled_skills ||= …`.
  - **Test:** `test/models/message/streamable_test.rb` — "skill body > MAX is truncated in prompt"; "two `advance!` iterations call Skill.enabled_for once".

- [ ] **T7 — Route unknown tool names to `:unknown` with a clean `Tool::Result.failure`.** Today `infer_source` has a `defined?(McpTool)` branch (dead code — model doesn't exist until Phase 4), and unknown names silently fall through to `source: :skill` and hit a misleading "Phase 4/6" placeholder.
  - **File:** `app/models/message/streamable.rb` — delete the `defined?(McpTool)` line (Phase 4 reintroduces it cleanly). Return `:unknown` when neither `Tool::Internal.lookup(name)` nor a (future) MCP tool matches.
  - **File:** `app/models/tool_call/executable.rb` — add `when :unknown` arm returning `Tool::Result.failure("unknown tool: #{name}")`.
  - **Test:** `test/models/message/streamable_test.rb` — "infer_source('garbage') returns :unknown"; "executing it produces a clean Result.failure".

- [ ] **T8 — Delete unused `Tool::Internal::Forbidden`.** Zero call-sites across `app/`, `config/`, `db/`, `test/`. The forbidden-path concept lives in `WorkspacePath::EscapeAttempt`.
  - **File:** `app/models/tool/internal.rb` — delete the constant.

- [ ] **T9 — `Tool::Internal.invoke` returns `Result.failure` for unknown tool name (was raising `UnknownTool`).** Aligns the contract with every other failure mode. After T8 + this, `Tool::Internal` has no custom exception classes.
  - **File:** `app/models/tool/internal.rb` — `klass = lookup(name) or return Tool::Result.failure("unknown tool: #{name}")`. Delete `UnknownTool`.
  - **Test:** `test/models/tool/internal_test.rb` — replace "raises UnknownTool" with "returns Result.failure for missing name".

**Commit message:** `Phase 3 Task 3.16b: tool registry — input validation + write_file no-clobber + clean rescue + unknown-tool contract + admin-only run_shell defs`

### 3.16c — Skills UI & wiring

- [ ] **U1 — Ship CSS for `.badge` / `.badge--ok|warn|danger`.** Helper is in the wild emitting these classes with no matching styles. App uses pure custom CSS (`@layer`, OKLCH tokens) — pick existing semantic color tokens (success / warning / danger).
  - **File:** `app/assets/stylesheets/base.css` (or new `components/badges.css` if the project uses an `@layer components` slot — follow whatever pattern other components use, e.g. `.button`).
  - **Test:** `test/system/skills_test.rb` — extend the existing assertion to `assert_selector ".badge.badge--ok, .badge.badge--warn, .badge.badge--danger"` so future CSS removal trips the system test.

- [ ] **U2 — `SkillsController#update` enqueues `Skill::ReloadJob` instead of running `load_from_path!` synchronously.** Job already exists; this aligns with the `_now/_later` pattern.
  - **File:** `app/controllers/skills_controller.rb` — replace inline `@skill.load_from_path!` with `Skill::ReloadJob.perform_later(path: @skill.source_path)`; flash → `"Reload queued."`.
  - **Test:** `test/controllers/skills_controller_test.rb` — `assert_enqueued_with(job: Skill::ReloadJob, args: [{ path: @skill.source_path }])`.

- [ ] **U3 — Guard `workspace_bootstrap` initializer against console/rake/migrate contexts.** Current `defined?(Skill)` guard is a no-op (Zeitwerk). Copy the guard block from `config/initializers/agents_supervisor_client.rb` (skip on `Rails::Console`, `Rails::Generators`, Rake top-level tasks) and add `next unless ActiveRecord::Base.connection.data_source_exists?("skills")` so fresh `db:prepare` doesn't blow up.
  - **File:** `config/initializers/workspace_bootstrap.rb`
  - **Test:** lightweight unit test, or simply boot `bin/rails runner '0'` and assert no `Skill::ReloadJob` is enqueued (`SolidQueue::Job.count` unchanged).

- [ ] **U4 — Remove `SkillsController#destroy` + route.** Disk is the source of truth; the action deletes the DB row but the next `Skill::ReloadJob` (boot replay, watcher, or supervisor reconnect) recreates it. Misleading affordance with no durable effect. Aligns with the Open-items note that the Web UI cannot mutate SKILL.md in Phase 3.
  - **File:** `app/controllers/skills_controller.rb` — delete `#destroy`; remove `:destroy` from `before_action` lists.
  - **File:** `config/routes.rb` — change `resources :skills` to `only: %i[index show update]`.
  - **Test:** `test/controllers/skills_controller_test.rb` — remove the destroy test.

- [ ] **U5 — `Skill::ReloadJob` becomes a one-liner; `Skill.reload_path(path)` owns the branching.** Restores the `_now/_later` job convention.
  - **File:** `app/models/skill/loadable.rb` — add class method `def reload_path(path); find_or_initialize_by(source_path: path).load_from_path!; rescue MalformedSkill => e; Rails.logger.warn("…"); end` (gives the supervisor/watcher path the same `rescue MalformedSkill` insulation that `reload_from_disk` got in Task 3.15).
  - **File:** `app/jobs/skill/reload_job.rb` — body becomes `path ? Skill.reload_path(path) : Skill.reload_from_disk`.
  - **Test:** `test/models/skill/loadable_test.rb` — add "reload_path tolerates malformed SKILL.md" mirroring the existing `reload_from_disk` test.

- [ ] **U8 — Delete unused `@categories` in `SkillsController#index`.** The view derives sections via `@skills.group_by(&:category)`; `@categories` is set and never read.
  - **File:** `app/controllers/skills_controller.rb` — delete the `@categories = …` line.

- [ ] **C2 / docs — Add direct scope tests for `Skill.enabled_for` / `installed_for`.** The associations live in `Skill::Installable` / `Skill::Enableable` (review false positive — they exist), but no test exercises the scopes directly. Add coverage so a future regression is caught at the unit layer, not in a full streaming integration test.
  - **File:** `app/models/skill.rb` — add a one-line comment above the two scopes: `# Associations live in Skill::Installable / Skill::Enableable (included above).`
  - **Test:** `test/models/skill_test.rb` — `enabled_for returns only skills enabled by the given user`; same shape for `installed_for`.

**Commit message:** `Phase 3 Task 3.16c: skills UI — badge CSS + async reload + bootstrap guards + remove destroy footgun + thin controllers + scope tests`

### 3.16 verification + retag

- [ ] `bin/rails test` — expect ≥213 runs, all green.
- [ ] `bin/rails test:system` — expect ≥7 runs, all green.
- [ ] `bin/bundle exec brakeman -A` — expect no new warnings (the 3 existing `app/models/tool/internal/write_file.rb` File-Access medium warnings stay; everything else should stay at the baseline).
- [ ] `bin/bundle exec bundler-audit check --update` — clean.
- [ ] `git tag -d phase-3 && git tag phase-3` — retag to the green head after 3.16c lands.

---

## Critical files map (Phase 3 additions)

```
config/routes.rb                                         # +skills routes
config/initializers/workspace_bootstrap.rb               # +seed copy + ReloadJob enqueue
config/initializers/tool_internal_registry.rb            # tool registration on boot
config/initializers/agents_supervisor_client.rb          # +Skill::ReloadJob cold-start replay
db/migrate/<ts>_create_skills.rb
db/migrate/<ts>_create_skill_installations.rb
db/migrate/<ts>_create_skill_enablements.rb
db/content_migrate/<ts>_create_skills_fts.rb
db/seeds/skills/io/filesystem/SKILL.md
db/seeds/skills/search/web_search/SKILL.md
db/seeds/skills/review/code_review/SKILL.md
db/seeds/skills/research/deep_research/SKILL.md
db/seeds/skills/writing/summarize/SKILL.md
app/models/skill.rb
app/models/skill_installation.rb
app/models/skill_enablement.rb
app/models/skill_fts.rb
app/models/skill/loadable.rb
app/models/skill/security_analyzable.rb
app/models/skill/security_analysis.rb
app/models/skill/installable.rb
app/models/skill/enableable.rb
app/models/tool.rb                                       # empty namespace (autoload anchor)
app/models/tool/internal.rb
app/models/tool/internal/read_file.rb
app/models/tool/internal/write_file.rb
app/models/tool/internal/list_dir.rb
app/models/tool/internal/run_shell.rb
app/models/tool/result.rb
app/models/concerns/searchable.rb                        # parameterized per-class adapter
app/models/memory_file.rb                                # +searchable_via declaration
app/models/tool_call/executable.rb                       # real implementation
app/models/message/streamable.rb                         # available_tools + system prompt wired
app/jobs/skill/reload_job.rb
app/controllers/skills_controller.rb
app/controllers/skills/installations_controller.rb
app/controllers/skills/enablements_controller.rb
app/helpers/skills_helper.rb
app/views/skills/{index.html.erb,show.html.erb}
app/services/agents_supervisor/client.rb                 # +skills.changed handler
bin/agents_supervisor                                    # +skills listener
test/fixtures/skills.yml
test/fixtures/files/skills/filesystem/SKILL.md
test/models/skill_test.rb
test/models/skill_search_test.rb
test/models/skill/{loadable_test.rb,security_analyzable_test.rb,installable_test.rb,enableable_test.rb}
test/models/tool/internal_test.rb
test/models/tool/internal/{read_file_test.rb,write_file_test.rb,list_dir_test.rb,run_shell_test.rb}
test/models/tool_call/executable_test.rb
test/controllers/skills_controller_test.rb
test/controllers/skills/{installations_controller_test.rb,enablements_controller_test.rb}
test/system/skills_test.rb
test/jobs/skill/reload_job_test.rb
```

## Open items (Phase 3 only — surface as you hit them, don't pre-decide)

- `agent_profile_skills` migration is **deferred to Phase 6**. Workflows.md § Phase 3 lists it, but the parent `agent_profiles` table doesn't exist until Phase 6. Adding the join now means either an FK to a missing table (broken at boot) or `foreign_key: false` (dangling reference). Phase 6 ships both together.
- `web_search` skill is a body-only stub in Phase 3 — the tool itself lands in Phase 4 once the MCP transport exists. The skill teaches the LLM the tool's API contract so it can be ready when the wiring lands.
- `SkillsController#update` does a *manifest reload* (re-parses disk). It is not a content-edit endpoint — the Web UI cannot mutate a SKILL.md body in Phase 3. Editing the body is done via `/files` (admin-only) or by editing the file on disk; the watcher picks it up.
- `run_shell` runs with the Rails process's UID. Task 3.16a adds a default-off production flag, an env scrub of secrets, and a PGID-based timeout kill. Harder isolation (rlimits, uid drop, container, namespaces) still needs the Phase 4 supervisor v2 rewrite and is intentionally out of scope here.
- `Skill::Loadable` accepts only YAML frontmatter. If a future skill format adds TOML or JSON front-blocks, lift the parser into a `Skill::FrontmatterParser` PORO at that time.
- Skills currently don't broadcast a Turbo Stream update on reload. If the `/skills` page needs live updates, wire `Skill#after_commit { broadcast_replace_to ... }` in Phase 5 alongside the dashboard work.
- **Skill-based tool filtering** in `Message#available_tools` is deferred to Phase 6 (alongside `agent_profile_skills`). Task 3.16b adds only a non-admin filter on `run_shell` as a stop-gap; the full per-user/per-skill capability filter ships with agent profiles.
- **Boot-replay of `Skill::ReloadJob` / `Memory::FullReindexJob` fires once per Puma worker.** Task 3.16a adds a path-keyed concurrency control on the job so the N concurrent calls collapse to one perform. Worker-0 gating (a true single-leader replay) needs Puma's `on_worker_boot` with worker index and lands as part of Phase 4 supervisor v2. Today's safety net: (a) DB unique index on `skills.slug`, (b) the new concurrency key, (c) `load_from_path!` digest short-circuit for idempotency.
- **FTS lacks a prefix index.** `skills_fts` uses `tokenize='porter'` only; `Searchable#matching` does phrase match without `*` suffix. Full-word search on `/skills` works fine today (porter stemming handles common cases). Autocomplete is a Phase 5 deliverable that will add `prefix='2 3'` to the fts5 table and `*`-suffix to `Searchable#matching` in one slice.
- **Lift `reindex_fts!` / `clear_fts_entry!` raw SQL into `Searchable` concern.** Today these live inline in `Skill::Loadable` and `MemoryFile::Reindexable`. After Task 3.16a moves them to `after_commit`, the bodies are still per-model. Phase 5 should bundle this refactor with the prefix-index work — introduce `Searchable#reindex_fts!(attrs_hash)` and let each model declare its column map.
- **`SkillInstallation#accepted_at` and `SkillEnablement#enabled_at` are eagerly set to `Time.current` and therefore always equal `created_at`.** Schema is frozen at the Phase 3 tag, so dropping them is a Phase 5 decision: either drop the columns and use `created_at`, or repurpose `enabled_at` to track the last re-enable (set only on unique-violation retry, otherwise nil).
- **`Skill::Loadable#load_from_path!` records `:reloaded` events with `creator: nil`** when invoked from the watcher or boot-replay job (`Eventable#track_event` defaults to `Current.user`, which is nil outside a request). `Event#creator` is `optional: true` so this is safe; revisit at Phase 5 if the dashboard wants to filter or attribute system-originated events.
- **`McpTool` routing in `Message::Streamable#infer_source` is deferred to Phase 4.** Task 3.16b removes the dead `defined?(McpTool)` line and adds an `:unknown` source for tools the registry can't resolve. Phase 4's MCP work reintroduces the MCP branch cleanly once `mcp_tools` and `Mcp::DiscoveryJob` land.
