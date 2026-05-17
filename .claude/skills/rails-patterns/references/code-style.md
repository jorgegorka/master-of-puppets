# Code Style

Stylistic conventions used across the codebase. They go beyond standard
Ruby/Rails style; expect rubocop to flag deviations.

## Conditional returns — expanded over guard clauses

Default to expanded `if/else`. Guard clauses are noisier than they look
once a method has more than one early return.

```ruby
# ✗ Avoid — guard clause for a one-line method
def todos_for_new_group
  ids = params.require(:todolist)[:todo_ids]
  return [] unless ids
  @bucket.recordings.todos.find(ids.split(","))
end

# ✓ Prefer — expanded conditional
def todos_for_new_group
  if ids = params.require(:todolist)[:todo_ids]
    @bucket.recordings.todos.find(ids.split(","))
  else
    []
  end
end
```

**Exception**: use a guard clause at the very top of a method when the
body that follows is non-trivial (many lines) and the early return is
the obvious thing for a reader to see first:

```ruby
def after_recorded_as_commit(recording)
  return if recording.parent.was_created?

  if recording.was_created?
    broadcast_new_column(recording)
  else
    broadcast_column_change(recording)
  end
end
```

If the body is short, an `if/elsif/else` reads better.

## Method ordering

Classes are ordered top to bottom:

1. `class` methods (or `class << self` block)
2. Public instance methods (`initialize` first if present)
3. Private methods

```ruby
class Task < ApplicationRecord
  # 1. class methods
  class << self
    def create_with_assignee(attrs, user:)
      # …
    end
  end

  # 2. public instance methods
  def initialize(*)
    super
  end

  def pause
    # …
  end

  # 3. private methods
  private
    def assign_number
      # …
    end
end
```

## Private methods — invocation order

Private methods are ordered vertically by the order they're called from
public methods. Reading top-to-bottom should follow the execution flow.

```ruby
def some_method
  method_1
  method_2
end

private
  def method_1
    method_1_1
    method_1_2
  end

  def method_1_1; end
  def method_1_2; end

  def method_2
    method_2_1
  end

  def method_2_1; end
```

Don't alphabetise. Don't group by type. Group by call-flow.

## Visibility modifiers — no blank line, indent the body

`private` is indented at the same level as the methods it modifies, with
no blank line after it. The methods underneath are indented one extra
level.

```ruby
class SomeClass
  def public_method
    # …
  end

  private
    def private_method_one
      # …
    end

    def private_method_two
      # …
    end
end
```

This pattern visually communicates "everything below here is private to
this class" — the indentation makes the scope obvious.

**Exception** for modules whose entire body is private: place `private`
at the top with an extra blank line, and don't indent the bodies:

```ruby
module SomeModule
  private

  def helper_one
    # …
  end

  def helper_two
    # …
  end
end
```

This shape is rare; the indented form is the default.

## Bang methods (`!`)

Only use `!` for methods that have a non-bang counterpart that differs
in behaviour. The bang signals "this is the raising version of the same
operation."

```ruby
# ✓ Good — paired
def save     ; end   # returns false on failure
def save!    ; end   # raises on failure

def update(attrs)  ; end
def update!(attrs) ; end
```

```ruby
# ✗ Bad — no counterpart, just trying to look dangerous
def destroy!
def process!
def archive!
```

Many destructive methods in Rails and Ruby don't end with `!`. Don't
add `!` to flag "this changes things". Use intention-revealing names
instead.

## Other small rules

- **One-line callbacks → lambdas.** Reserve named methods for callbacks
  that need a name to explain themselves:
  ```ruby
  after_save -> { workflow.touch }, if: :published?
  ```
- **`scope :name, ->`** rather than passing a relation directly. The
  lambda defers evaluation so the scope is stable across class reloads.
- **Keep names domain-flavoured.** `gild`, `pause`, `triage_into` — not
  `mark_special`, `set_state`, `change_status`.

## See also

- `references/models.md` — where most of these style rules apply
- `references/controllers.md` — three-line action shape is the
  controller manifestation of this aesthetic
