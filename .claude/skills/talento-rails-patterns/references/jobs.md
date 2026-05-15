# Background Jobs

Jobs in this codebase are ultra-thin. The synchronous logic lives on
the model; the job's `perform` is one or two lines that calls back into
it. Multi-tenancy (the `Current.account` context) is captured and
restored automatically — you never pass `account:` to a job.

## The `_now` / `_later` pattern

For every async operation, you write three things:

1. A **synchronous method** on the model (often a concern). The bare
   verb name. This is where the logic lives.
2. An **async wrapper** with the same name plus `_later`. One line:
   enqueues the job.
3. A **job class** whose `perform` calls the synchronous method.

```ruby
# app/models/concerns/notifiable.rb
module Notifiable
  extend ActiveSupport::Concern

  included do
    has_many :notifications, as: :source, dependent: :destroy
    after_create_commit :notify_recipients_later
  end

  def notify_recipients                          # ← sync
    Notifier.for(self)&.notify
  end

  private
    def notify_recipients_later                  # ← async wrapper
      NotifyRecipientsJob.perform_later self
    end
end
```

```ruby
# app/jobs/notify_recipients_job.rb
class NotifyRecipientsJob < ApplicationJob
  def perform(notifiable)
    notifiable.notify_recipients                 # ← back to the model
  end
end
```

The flow on save: record committed → `after_create_commit` calls
`notify_recipients_later` → enqueues the job → worker runs
`notify_recipients` on the model.

## Why this shape

- **Logic is testable synchronously.** Calling `comment.notify_recipients`
  in a test is fast and assertable. You don't need to drain queues to
  test logic.
- **The same code path runs synchronously and asynchronously.** From a
  console or another model you can call the sync method directly without
  going through the queue.
- **Naming makes intent obvious.** `record.notify_recipients` is
  clearly synchronous; `record.notify_recipients_later` is clearly
  async. No reader has to guess.

## Ultra-thin `perform`

A job's `perform` is 1–3 lines. If it's longer, you're putting logic in
the wrong place.

```ruby
class Webhook::DeliveryJob < ApplicationJob
  queue_as :webhooks

  def perform(delivery)
    delivery.deliver
  end
end

class ExportAccountDataJob < ApplicationJob
  queue_as :backend

  def perform(export)
    export.build
  end
end
```

If a job needs branching, exception handling, or more than a couple of
lines of orchestration, that orchestration belongs on the model as a
method named for what it does.

## Multi-tenancy is automatic

The project's `ActiveJob` extension captures `Current.account` when a
job is created and restores it when the job runs. You should not pass
account explicitly.

```ruby
# ✗ Don't do this
SomeJob.perform_later(record, account: Current.account)

# ✓ Just enqueue
SomeJob.perform_later(record)
# Current.account is restored inside perform; queries scope correctly.
```

This is set up in `config/initializers/active_job.rb`. Inside a job:

```ruby
def perform(comment)
  # Current.account is set — these queries are scoped automatically:
  comment.card.watchers.each do |user|
    Notification.create!(user: user, source: comment)
  end
end
```

In tests, just set `Current.session` in `setup` and the same
automatic scoping applies.

## `enqueue_after_transaction_commit`

The same `ActiveJob` extension sets
`self.enqueue_after_transaction_commit = true`. Combined with
`after_create_commit`, this means jobs enqueued during a transaction
only actually go on the queue once the transaction commits. You don't
have to manage that yourself — but it's worth knowing why
`after_create_commit` (not `after_create`) is the right callback for
async work.

## Async cleanup outside transactions

When you have a multi-step state change that also kicks off async
work, the transaction wraps the state change and the async call sits
**outside** it:

```ruby
def handle_workflow_change
  old_workflow = account.workflows.find_by(id: workflow_id_before_last_save)

  transaction do
    update! column: nil
    track_event "workflow_changed",
      particulars: { old: old_workflow.name, new: workflow.name }
    grant_access_to_assignees unless workflow.all_access?
  end

  remove_inaccessible_notifications_later   # outside transaction
end
```

The async call shouldn't roll back the state change if it fails to
enqueue, and the worker should see the committed state.

## Testing

Test the synchronous logic directly. Test the async wrapper enqueues
the right job. Don't test logic by draining the queue unless you're
specifically testing async integration.

```ruby
# Test the sync method
test "notify_recipients sends to watchers" do
  comment.notify_recipients
  assert_equal 2, Notification.count
end

# Test the async wrapper
test "notify_recipients_later enqueues job" do
  assert_enqueued_with(job: NotifyRecipientsJob, args: [comment]) do
    comment.notify_recipients_later
  end
end

# Test the callback enqueues on save
test "create enqueues notification job" do
  assert_enqueued_with(job: NotifyRecipientsJob) do
    Comment.create!(card: card, body: "hi")
  end
end
```

## Recipe — adding a new async operation

1. Write a synchronous method on the model (or a concern). The bare
   verb. Put the logic here.
2. Add a private `_later` wrapper that enqueues the job.
3. Create the job under `app/jobs/`. `perform` calls back into the
   model.
4. If the work happens automatically on save, wire it up with
   `after_create_commit :verb_later` (or `after_update_commit`).
5. Test the sync method (assertions on data), test the async wrapper
   (assertions on the queue).

```ruby
# 1. sync logic
def deliver
  # actual delivery
end

# 2. async wrapper
private
  def deliver_later
    DeliverJob.perform_later self
  end

# 3. job
class DeliverJob < ApplicationJob
  queue_as :backend
  def perform(delivery) = delivery.deliver
end

# 4. callback (if applicable)
after_create_commit :deliver_later
```

## See also

- `references/models.md` — where the sync logic lives
- `references/testing.md` — `assert_enqueued_with` patterns
- `references/recipes.md` — full end-to-end walkthrough
