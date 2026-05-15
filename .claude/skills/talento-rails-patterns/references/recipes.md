# Recipes — Multi-File Workflows

When a feature touches several layers at once, follow these end-to-end
recipes. Each one lists every file you'll create or modify in order.

The examples assume the domain model from `agents.md` — `Task`,
`Agent`, `TaskRun`, `Workflow` — but the shape is the same for any
model.

## Recipe 1 — Adding a new state to a model

Say you want a `paused` state on `Task`. State here means a separate
record (`Task::Pause`) whose presence indicates the state, not a boolean
column.

### Files you'll touch

1. `db/migrate/<timestamp>_create_task_pauses.rb` — migration
2. `app/models/task/pause.rb` — the state model
3. `app/models/task/pausable.rb` — the concern with the API
4. `app/models/task.rb` — include the concern
5. `config/routes.rb` — RESTful `resource :pause`
6. `app/controllers/tasks/pauses_controller.rb` — thin controller
7. `test/models/task/pausable_test.rb` — model test
8. `test/fixtures/task_pauses.yml` — fixtures (if needed)

### Step 1 — Migration and state model

```ruby
class CreateTaskPauses < ActiveRecord::Migration[7.1]
  def change
    create_table :task_pauses do |t|
      t.references :task,    null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.timestamps
    end
  end
end
```

```ruby
# app/models/task/pause.rb
class Task::Pause < ApplicationRecord
  belongs_to :task
  belongs_to :user
  belongs_to :account, default: -> { task.account }
end
```

### Step 2 — Concern with the API

```ruby
# app/models/task/pausable.rb
module Task::Pausable
  extend ActiveSupport::Concern

  included do
    has_one :pause, dependent: :destroy

    scope :paused,  -> { joins(:pause) }
    scope :running, -> { where.missing(:pause) }
  end

  def paused?  = pause.present?
  def running? = !paused?

  def paused_by = pause&.user
  def paused_at = pause&.created_at

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

Note: scopes (`paused`, `running`), boolean queries (`paused?`,
`running?`), delegation helpers (`paused_by`, `paused_at`), and
intention-revealing action verbs (`pause`, `resume`) — not
`activate_pause`, not `update_pause_state`.

### Step 3 — Include the concern

```ruby
# app/models/task.rb
class Task < ApplicationRecord
  include Assignable, Eventable, Pausable, Watchable
  #                              ^^^^^^^^ add here
end
```

### Step 4 — Route as a singleton resource

```ruby
# config/routes.rb
resources :tasks do
  scope module: :tasks do
    resource :pause   # POST /tasks/:task_id/pause   → create
                      # DELETE /tasks/:task_id/pause → destroy
  end
end
```

Singular `resource`, not `resources`. This generates exactly `create`
and `destroy` actions.

### Step 5 — Thin controller

```ruby
# app/controllers/tasks/pauses_controller.rb
class Tasks::PausesController < ApplicationController
  include TaskScoped

  def create
    @task.pause

    respond_to do |format|
      format.turbo_stream { render_task_replacement }
      format.json { head :no_content }
    end
  end

  def destroy
    @task.resume

    respond_to do |format|
      format.turbo_stream { render_task_replacement }
      format.json { head :no_content }
    end
  end
end
```

### Step 6 — Test

```ruby
# test/models/task/pausable_test.rb
require "test_helper"

class Task::PausableTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  test "pause creates pause record and event" do
    task = tasks(:writeup)

    assert_difference -> { Task::Pause.count }, +1 do
      assert_difference -> { Event.count }, +1 do
        task.pause
      end
    end

    assert task.paused?
    assert_equal "task_paused", Event.last.action
  end

  test "resume removes pause record" do
    task = tasks(:writeup)
    task.pause

    assert_difference -> { Task::Pause.count }, -1 do
      task.resume
    end

    assert task.running?
  end

  test "paused scope" do
    task = tasks(:writeup)
    task.pause

    assert_includes Task.paused,  task
    assert_not_includes Task.running, task
  end
end
```

That's the whole feature: a state model, a concern, an include line, a
route, a controller, a test.

## Recipe 2 — Adding event tracking to an existing action

When an existing action should now record an event:

### Step 1 — Ensure `Eventable` is included

```ruby
class Task < ApplicationRecord
  include Eventable, …
end
```

### Step 2 — Call `track_event` inside the transaction

```ruby
def archive(user: Current.user)
  unless archived?
    transaction do
      update!(archived_at: Time.current)
      track_event :archived, creator: user      # add this
    end
  end
end
```

If the event carries context, add a `particulars:` hash. Keys read back
as strings, so name them for the consumer:

```ruby
def move_to(new_workflow)
  old = workflow.name

  transaction do
    update!(workflow: new_workflow)
    track_event :workflow_changed,
      particulars: { old: old, new: new_workflow.name }
  end
end
```

### Step 3 — Test the event

```ruby
test "archive tracks an event" do
  task = tasks(:writeup)

  assert_difference -> { Event.count }, +1 do
    task.archive
  end

  event = Event.last
  assert_equal "task_archived", event.action
  assert_equal users(:david), event.creator
end

test "move_to records old and new workflow names" do
  task     = tasks(:writeup)
  old_name = task.workflow.name
  new      = workflows(:other)

  task.move_to(new)

  event = Event.last
  assert_equal "task_workflow_changed", event.action
  assert_equal old_name,     event.particulars["old"]
  assert_equal new.name,     event.particulars["new"]
end
```

## Recipe 3 — Adding a background job

The `_now` / `_later` pattern, end to end.

### Step 1 — Sync method on the model

```ruby
# app/models/task.rb (or a concern)
def reindex
  Search::Indexer.for(self).reindex
end
```

The bare verb. This is the testable, callable-from-anywhere version.

### Step 2 — Async wrapper

```ruby
private
  def reindex_later
    ReindexJob.perform_later self
  end
```

One line. Always private unless something outside the class enqueues it.

### Step 3 — Job

```ruby
# app/jobs/reindex_job.rb
class ReindexJob < ApplicationJob
  queue_as :backend

  def perform(record)
    record.reindex
  end
end
```

Two lines of body. No logic.

### Step 4 — Callback (when work fires automatically)

```ruby
after_save_commit :reindex_later
```

`_commit`, not `after_save`. Jobs that fire from non-committed
transactions can race the database.

### Step 5 — Test both halves

```ruby
test "reindex updates the search index" do
  task = tasks(:writeup)
  task.reindex

  assert Search::Index.last.task_id == task.id
end

test "reindex_later enqueues ReindexJob" do
  assert_enqueued_with(job: ReindexJob, args: [task]) do
    task.reindex_later
  end
end

test "saving the task enqueues a reindex" do
  assert_enqueued_with(job: ReindexJob) do
    tasks(:writeup).update!(title: "new")
  end
end
```

## Cross-cutting checklist for any recipe

When the feature is "done", run through this:

- [ ] Resources, not custom routes (`resource :pause`, not `post :pause`).
- [ ] Controller actions are 3 lines.
- [ ] Model methods that change multiple things are wrapped in
      `transaction do`.
- [ ] Events are tracked via `track_event`, not hand-built.
- [ ] Async work uses `_later` and an ultra-thin job.
- [ ] `belongs_to :account` uses a lambda default where the parent
      provides it.
- [ ] Tests set `Current.session = sessions(:david)`.
- [ ] Tests assert on the state record, the event, and the query
      methods/scopes.

## See also

- `references/models.md` — pattern catalogue underlying the recipes
- `references/controllers.md` — the three-line action shape
- `references/jobs.md` — `_now`/`_later` and automatic multi-tenancy
- `references/testing.md` — `Current.session`, `assert_difference`,
  `assert_enqueued_with` idioms
