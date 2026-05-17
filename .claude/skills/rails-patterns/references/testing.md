# Testing

Tests in this codebase exercise model methods directly. Controllers are
so thin that integration tests on them just check routing and rendering;
the real assertions live in model tests where the business logic does.

## Setup: `Current.session` is mandatory

Lambda defaults like `default: -> { Current.user }` raise unless a
session is active. Almost every model test needs:

```ruby
require "test_helper"

class Task::PausableTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  # tests...
end
```

If you write a test and get `NoMethodError: undefined method '…' for nil`
on a `creator` or `account`, this is the cause 90% of the time.

The `sessions(:david)` fixture sets `Current.user` and (via lambda
defaults on `User`) `Current.account` automatically. Background jobs
that run during the test inherit that account context for free — see
`references/jobs.md`.

## What to assert

For state-changing model methods, assert on three things:

1. **The state model** is created or destroyed (`Card::Closure.count`,
   `Task::Pause.count`).
2. **The event** is tracked, including the `action` and any
   `particulars`.
3. **The query methods** answer correctly (`task.paused?`, scope
   membership).

```ruby
test "pause creates pause record and event" do
  task = tasks(:writeup)

  assert_difference -> { Task::Pause.count }, +1 do
    assert_difference -> { Event.count }, +1 do
      task.pause
    end
  end

  assert task.paused?
  assert_equal "task_paused", Event.last.action
  assert_equal users(:david), Event.last.creator
end

test "resume removes pause record" do
  task = tasks(:writeup)
  task.pause

  assert_difference -> { Task::Pause.count }, -1 do
    task.resume
  end

  assert task.running?
end
```

Use `assert_difference` (or `assert_no_difference`) for count
assertions — they read like the intent and give better failure
messages than two `count` calls bracketing the action.

## Asserting on `particulars`

When events carry context, assert it explicitly:

```ruby
test "moving workflows creates event with particulars" do
  task = tasks(:writeup)
  old_workflow = task.workflow
  new_workflow = workflows(:other)

  assert_difference -> { Event.count }, +1 do
    task.move_to(new_workflow)
  end

  event = Event.last
  assert_equal "task_workflow_changed", event.action
  assert_equal old_workflow.name, event.particulars["old"]
  assert_equal new_workflow.name, event.particulars["new"]
end
```

`particulars` is JSON; keys come back as strings. Don't expect
symbol-keyed access.

## Scope tests

Scopes are part of the public model API. Test them as you would any
method, asserting both inclusion and exclusion:

```ruby
test "paused scope" do
  task = tasks(:writeup)
  task.pause

  assert_includes Task.paused, task
  assert_not_includes Task.running, task
end
```

For composable scopes, test the composition:

```ruby
test "paused_by filters by user" do
  task = tasks(:writeup)
  task.pause(user: users(:david))

  assert_includes Task.paused_by(users(:david)), task
  assert_not_includes Task.paused_by(users(:other)), task
end
```

## Async work — synchronous logic vs queue assertions

Test the sync method for *what it does*; test the `_later` wrapper for
*that it enqueues the right job*.

```ruby
# Sync — fast, assertable
test "notify_recipients creates notifications" do
  comment.notify_recipients
  assert_equal 2, Notification.count
end

# Async wrapper — uses ActiveJob test helpers
test "notify_recipients_later enqueues the job" do
  assert_enqueued_with(job: NotifyRecipientsJob, args: [comment]) do
    comment.notify_recipients_later
  end
end

# The callback path — that saving the model enqueues the job
test "create enqueues notification job" do
  assert_enqueued_with(job: NotifyRecipientsJob) do
    Comment.create!(card: card, body: "hi")
  end
end
```

Only drain the queue with `perform_enqueued_jobs` when you're
specifically testing the integration between the callback, the queue,
and the resulting side effect.

## Controller tests are minimal

Because controllers are 3 lines, their tests just check routing,
authorisation, and rendering. The behaviour is tested at the model
level.

```ruby
class Tasks::PausesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:david)
  end

  test "create pauses the task" do
    task = tasks(:writeup)

    post task_pause_url(task)

    assert_response :success
    assert task.reload.paused?
  end

  test "destroy resumes the task" do
    task = tasks(:writeup)
    task.pause

    delete task_pause_url(task)

    assert_response :success
    assert task.reload.running?
  end
end
```

One assertion per HTTP behaviour is enough — the model test already
proved that `pause` does the right thing.

## Presenter tests

Presenters are plain Ruby classes — test them as such, no Rails-y
helpers needed:

```ruby
class User::FilteringTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @user = users(:david)
    @filter = Filter.new
  end

  test "show_tags? returns true when tags present" do
    @filter.tags = [tags(:bug)]
    filtering = User::Filtering.new(@user, @filter)

    assert filtering.show_tags?
  end

  test "cache_key changes when filter changes" do
    a = User::Filtering.new(@user, @filter).cache_key

    @filter.tags = [tags(:bug)]
    b = User::Filtering.new(@user, @filter).cache_key

    assert_not_equal a, b
  end
end
```

For presenters that emit HTML, assert on inclusion of expected content
and absence of HTML in plain-text outputs:

```ruby
test "to_html includes creator name" do
  description = Event::Description.new(events(:closed), users(:david))
  assert_includes description.to_html, events(:closed).creator.name
end

test "to_plain_text contains no tags" do
  description = Event::Description.new(events(:closed), users(:david))
  assert_no_match /<[^>]+>/, description.to_plain_text
end
```

## Common gotchas

- **`NoMethodError` on `account` or `creator`** — you forgot
  `Current.session = sessions(:david)` in `setup`.
- **`particulars` lookup returns nil** — keys are strings (`"old"`),
  not symbols (`:old`).
- **`assert_enqueued_with` finds no job** — check whether the test is
  running inside a transaction that prevents the
  `after_create_commit` callback from firing. Use
  `self.use_transactional_tests = false` in rare cases, but usually
  it's fine.
- **Job runs with the wrong account** — set `Current.session` in
  setup; the rest is automatic.
- **Asserting on `task.paused?` after `task.pause`** without reloading
  — pause is a `has_one`, so the instance state is fine, but if
  you've mutated through another instance, reload first.

## See also

- `references/models.md` — what the methods you're testing actually do
- `references/jobs.md` — `_now`/`_later` and the multi-tenancy capture
- `references/recipes.md` — full end-to-end pattern with tests
