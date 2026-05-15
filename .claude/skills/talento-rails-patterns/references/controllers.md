# Controllers

Controllers do three things: set instance variables from params, call
one model method, render or redirect. If a controller action grows
beyond that, the logic belongs in the model.

## The shape of an action

```ruby
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

That's the whole controller. Both actions are three statements: call a
model method, respond.

What controllers **don't** do:
- Build event records by hand (`Event.create!(action: …)`) — that's
  `track_event` on the model, called inside the transaction.
- Orchestrate multiple updates (`@task.update!(…); @task.events.create!(…);
  @task.notify_recipients`) — wrap them in a single model method that
  uses `transaction do`.
- Compute conditional state — that's a scope or a method on the model.
- Loop over collections to update them — that's a class method on the
  model.

## RESTful resource nesting — the most distinctive rule

**Never add custom action routes.** Every action creates, updates, or
destroys *something*. That something is a resource.

```ruby
# ✗ Anti-pattern — custom routes
resources :tasks do
  post   :pause
  delete :pause
  post   :gild
end

# ✓ Talento HQ pattern — RESTful resources
resources :tasks do
  scope module: :tasks do
    resource :pause     # POST /tasks/:task_id/pause   → create
                        # DELETE /tasks/:task_id/pause → destroy
    resource :goldness
    resource :watch
  end
end
```

`resource` (singular) generates `POST` and `DELETE` for create/destroy
of a singleton resource scoped to the parent. The controller goes
under `app/controllers/tasks/` and is named for the resource:
`Tasks::PausesController`, `Tasks::GoldnessesController`,
`Tasks::WatchesController`.

When you're tempted to add a custom action, ask: "what's the noun
behind this verb?"

| Verb         | Resource  |
|--------------|-----------|
| pause / resume | `Pause` |
| gild / ungild | `Goldness` |
| watch / unwatch | `Watch` |
| pin / unpin | `Pin` |
| assign / unassign (a user) | `Assignment` |
| close / reopen | `Closure` |
| comment on | `Comment` |

If the resource doesn't exist yet, create the model too — typically a
small ActiveRecord that just records the action (`belongs_to :task`,
`belongs_to :user`, `created_at`).

## Controller concerns

Loading and authorisation patterns repeat across controllers. Extract
them into concerns the moment the third controller needs the same
before_action.

```ruby
# app/controllers/concerns/task_scoped.rb
module TaskScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_task, :set_workflow
  end

  private
    def set_task
      @task = Current.user.accessible_tasks.find(params[:task_id])
    end

    def set_workflow
      @workflow = @task.workflow
    end

    def render_task_replacement
      render turbo_stream: turbo_stream.replace(
        [@task, :task_container],
        partial: "tasks/container",
        method: :morph,
        locals: { task: @task.reload }
      )
    end
end
```

Every nested controller then opens with `include TaskScoped` and has
`@task`, `@workflow`, and `render_task_replacement` available.

Authorisation belongs in concerns too:

```ruby
module WorkflowScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_workflow
  end

  private
    def set_workflow
      @workflow = Current.user.workflows.find(params[:workflow_id])
    end

    def ensure_permission_to_admin_workflow
      head :forbidden unless Current.user.can_administer_workflow?(@workflow)
    end
end
```

Create a controller concern when three or more controllers need the
same `before_action`, when resource loading is repeated, or when
authorisation checks are duplicated. Don't create one for a single
before_action used in one place.

## Finding records — use `Current.user.accessible_*`

Records are looked up through the current user's access, never with
`Model.find` directly. This enforces multi-tenancy and authorisation
in one call:

```ruby
# ✓ Scoped through the user
@task = Current.user.accessible_tasks.find(params[:task_id])

# ✗ Direct find — bypasses authorisation
@task = Task.find(params[:id])
```

When user-facing IDs use a different column than the database id
(e.g. cards exposed by `number`), look them up by that column:

```ruby
@card = Current.user.accessible_cards.find_by!(number: params[:card_id])
```

## Responding

Always use `respond_to do |format|` for actions that have multiple
representations. Turbo Streams for the live UI, JSON for API clients,
HTML for full-page falls back:

```ruby
respond_to do |format|
  format.turbo_stream { render_task_replacement }
  format.json { head :no_content }
end
```

For mutation actions that return no data, `head :no_content` is the
right JSON response. Don't render placeholder JSON bodies.

## When the action looks complex

If you find yourself writing:

```ruby
def create
  @task = @workflow.tasks.find(params[:task_id])
  @task.update!(status: "paused", paused_at: Time.current)
  @task.events.create!(action: "paused", creator: Current.user)
  NotifyWatchersJob.perform_later(@task)
  …
end
```

stop and refactor. The fix is a model method:

```ruby
# In Task::Pausable
def pause(user: Current.user)
  unless paused?
    transaction do
      create_pause! user: user
      track_event :paused, creator: user
    end
    notify_watchers_later
  end
end
```

Then the controller becomes:

```ruby
def create
  @task.pause

  respond_to do |format|
    format.turbo_stream { render_task_replacement }
  end
end
```

The litmus test: every controller action should be readable in five
seconds. If it isn't, push logic into the model.

## See also

- `references/models.md` — what those one-line model calls do underneath
- `references/recipes.md` — full walkthrough including routes, controller, model, test
