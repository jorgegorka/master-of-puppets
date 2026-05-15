# Models

Models are the heart of the codebase. They contain business logic, are
composed from many small concerns, and expose APIs that read like the
domain (not like a database).

## Concern architecture

Two flavours of concerns, never mixed up:

**Shared concerns** live in `app/models/concerns/` and use adjective
naming. They're reusable across unrelated models: `Eventable`,
`Notifiable`, `Searchable`, `Attachments`, `Mentions`, `Storage::Tracked`.

**Model-specific concerns** live in `app/models/<model>/` and use
namespaced naming. They encapsulate a single behaviour for a single
model: `Task::Pausable`, `Task::Assignable`, `Agent::Configurable`.

A typical model just lists its concerns:

```ruby
class Task < ApplicationRecord
  include Assignable, Eventable, Pausable, Postponable, Watchable

  belongs_to :workflow
  belongs_to :account, default: -> { workflow.account }
  belongs_to :creator, class_name: "User", default: -> { Current.user }
end
```

Each concern adds one capability. The model itself reads as a table of
contents.

### Anatomy of a concern

```ruby
module Task::Pausable
  extend ActiveSupport::Concern

  included do
    has_one :pause, dependent: :destroy

    scope :paused, -> { joins(:pause) }
    scope :running, -> { where.missing(:pause) }
  end

  def paused?
    pause.present?
  end

  def running?
    !paused?
  end

  def pause(user: Current.user)
    unless paused?
      transaction do
        create_pause! user: user
        track_event :paused, creator: user
      end
    end
  end

  def resume(user: Current.user)
    if paused?
      transaction do
        pause.destroy
        track_event :resumed, creator: user
      end
    end
  end
end
```

Pattern: `extend ActiveSupport::Concern` first, an `included do` block
for class-level wiring (associations, scopes, callbacks), then instance
methods. The state is a separate model (`Pause`) joined via
`has_one :pause` — the boolean `paused?` is a query, not a column.

### When to create a concern

Make a shared concern when three or more **unrelated** models need the
same cross-cutting behaviour (events, search, notifications, attachments).

Make a model-specific concern when one model has 50+ lines of cohesive
behaviour — a state machine, a calculation, a workflow step.

Don't make a concern for one or two simple methods or for unrelated
methods grouped together for convenience.

### Template-method pattern in shared concerns

Shared concerns offer override points; model-specific concerns include
the shared one and override:

```ruby
module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  def track_event(action, creator: Current.user, **particulars)
    if should_track_event?
      events.create!(
        action: "#{eventable_prefix}_#{action}",
        creator:, eventable: self, particulars:
      )
    end
  end

  private
    def should_track_event? = true
    def eventable_prefix    = self.class.name.demodulize.underscore
end

module Task::Eventable
  extend ActiveSupport::Concern
  include ::Eventable

  private
    def should_track_event?
      published?
    end
end
```

## Intention-revealing APIs

Method names should read like domain language. Boolean methods come in
pairs:

```ruby
def paused?  = pause.present?
def running? = !paused?
```

Action methods are imperative verbs that mirror the domain:

```ruby
def pause   ; end
def resume  ; end
def gild    ; end
def ungild  ; end
def close   ; end
def reopen  ; end
```

Not `process`, `handle`, `do_something`, `update_state`,
`set_paused_flag`, `create_pause_record`. Those leak implementation.

Delegation makes APIs read naturally:

```ruby
def paused_by = pause&.user      # better than `task.pause&.user`
def paused_at = pause&.created_at
```

Complex multi-step actions wrap state changes in a transaction and
track an event:

```ruby
def handle_workflow_change
  old_workflow = account.workflows.find_by(id: workflow_id_before_last_save)

  transaction do
    update! column: nil
    track_event "workflow_changed",
      particulars: { old: old_workflow.name, new: workflow.name }
    grant_access_to_assignees unless workflow.all_access?
  end

  remove_inaccessible_notifications_later  # async, outside the transaction
end
```

Async cleanup goes **outside** the transaction — it can fail
independently without rolling back the state change.

## Smart association defaults (lambda defaults)

Use lambdas to derive associations from context. Order matters: declare
the association you depend on first.

```ruby
class Task < ApplicationRecord
  belongs_to :workflow                                        # declare first
  belongs_to :account, default: -> { workflow.account }       # then derive
  belongs_to :creator, class_name: "User", default: -> { Current.user }
end
```

Then callers stay clean:

```ruby
Task.create!(workflow: w, title: "Foo")
# account and creator filled in automatically
```

Use lambda defaults always for `account` (multi-tenancy) and
`creator`/`user` (audit). Consider them for any value that always comes
from a parent association. Don't use them for values that need
validation or non-trivial computation — use a callback or explicit
method instead.

## Scopes that tell stories

Scope names describe the business concept, not the SQL.

```ruby
scope :paused,   -> { joins(:pause) }
scope :running,  -> { where.missing(:pause) }

scope :recently_paused_first, -> { paused.order(pauses: { created_at: :desc }) }
scope :paused_at_window, ->(window) { paused.where(pauses: { created_at: window }) }
scope :paused_by, ->(users) { paused.where(pauses: { user_id: Array(users) }) }
```

Good: `paused`, `running`, `due_to_be_postponed`. Bad: `with_pauses`,
`where_pause_present`, `paused_list` (returning an array — never
break the chain).

Map UI inputs to scopes inside the model, not in controllers:

```ruby
scope :indexed_by, ->(index) do
  case index
  when "paused"   then paused
  when "running"  then running
  when "due_soon" then due_to_be_postponed
  else                 all
  end
end
```

For preloading, define an explicit preload scope:

```ruby
scope :with_users, -> {
  preload(creator: [:avatar_attachment, :account], assignees: [:account])
}

scope :preloaded, -> {
  with_users.preload(:workflow, :pause, :tags)
}
```

Controllers then say `workflow.tasks.preloaded` and N+1 queries
disappear.

## Callbacks — minimal philosophy

Use callbacks for data consistency (setting required fields), triggering
async operations, and touching associations for cache invalidation.
Don't use them for business logic.

Common shapes:

```ruby
# Set required data before save
before_create :assign_number

# Async work after the transaction commits — note _commit
after_create_commit :notify_recipients_later

# Touch parents for cache invalidation
after_save  -> { workflow.touch }, if: :published?
after_touch -> { workflow.touch }, if: :published?

# Conditional, only when the relevant attribute changed
after_update :handle_workflow_change, if: :saved_change_to_workflow_id?
```

Why `_commit` for async work: a job enqueued in `after_create` could run
before the transaction commits, finding nothing in the database. The
`_commit` variant fires after the commit, never on rollback.

For one-liner callbacks, prefer a lambda; reach for a method when the
logic is non-trivial.

Anti-patterns to refactor away:

- 50-line `after_create` callbacks → make the publishing/closing/
  pausing an explicit method on the model and call it from the
  controller.
- `before_destroy :prevent_if_has_children` → expose `can_destroy?` and
  let the caller decide.

## Presenters

Presenters package view-ready data and conditional display logic. They
live in `app/models/` (not a separate `app/presenters/` tree), use
domain-organized naming (`User::Filtering`, not `FilteringPresenter`),
and are plain Ruby classes.

```ruby
class User::Filtering
  attr_reader :user, :filter, :expanded

  def initialize(user, filter, expanded: false)
    @user, @filter, @expanded = user, filter, expanded
  end

  def boards
    @boards ||= user.boards.ordered_by_recently_accessed
  end

  def expanded? = @expanded
  def show_tags? = filter.tags.any?

  def cache_key
    ActiveSupport::Cache.expand_cache_key(
      [user, filter, expanded?, boards],
      "user-filtering"
    )
  end
end
```

Patterns:
- Memoize collections with `@var ||=`.
- Boolean methods (`expanded?`, `show_tags?`) for view conditionals.
- A `cache_key` method to enable fragment caching.
- For HTML generation, include the minimum ActionView helpers needed
  (`ActionView::Helpers::TagHelper`, `ERB::Util`) and offer `to_html`
  plus `to_plain_text`.

Instantiation patterns:
- Controller concern: load `@user_filtering` in a `before_action` and
  let views read it.
- Factory method on a model: `event.description_for(user)` returning a
  presenter.

Test presenters like any Ruby class — they're not framework objects.

## Events as audit trail

Models that need a history include `Eventable` (or the model-specific
override). Every significant action calls `track_event` inside its
transaction:

```ruby
def pause(user: Current.user)
  unless paused?
    transaction do
      create_pause! user: user
      track_event :paused, creator: user
    end
  end
end
```

The `particulars:` hash stores action-specific data as JSON for the
timeline, webhooks, and notifications:

```ruby
track_event "workflow_changed",
  particulars: { old: old_name, new: new_name }
```

`auto_*` variants (e.g. `auto_pause`) use a different event name to
distinguish system-triggered from user-triggered actions:

```ruby
def auto_pause(user: Current.user)
  pause(user: user, event_name: :auto_paused)
end
```

## See also

- `references/controllers.md` — how controllers call into these methods
- `references/jobs.md` — `_now`/`_later` wrappers for async model work
- `references/testing.md` — asserting on events, scopes, and transactions
- `references/recipes.md` — end-to-end "add a new state" walkthrough
