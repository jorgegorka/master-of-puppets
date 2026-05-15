---
name: talento-rails-patterns
description: Use whenever working on Ruby/Rails code in master-of-puppets — creating or modifying models, controllers, background jobs, tests, routes, concerns, presenters, or anything in app/, test/, lib/, or config/routes.rb. Encodes the Talento HQ opinionated patterns: concern-driven models, intention-revealing APIs, lambda association defaults, business-language scopes, sparing callbacks, thin controllers, RESTful resource nesting (never custom action routes), the _now/_later background-job pattern, automatic multi-tenancy via Current, and Talento HQ code-style conventions (expanded conditionals, method ordering, private indentation, bang naming). Load this skill BEFORE writing or editing Rails code so the output matches the team's idioms — even for "simple" changes that look like they don't need it.
---

# Talento HQ Rails Patterns

This project follows the opinionated Rails patterns originally codified
at Talento HQ. The canonical source is `docs/patterns-and-best-practices.md`;
this skill is the working distillation that loads when you write code.

## The Worldview

Business logic lives in **rich models** composed from many small concerns.
Controllers and jobs are **thin orchestrators** that call one model method
and respond. State changes are modeled as **RESTful resources**, never as
custom action routes. **Events** are the audit trail and notification source.
**Multi-tenancy** is automatic via `Current` — you almost never pass
`account` explicitly.

When in doubt, push logic down into the model and ask "what resource is
this action creating, updating, or destroying?"

## Universal rules — apply on every edit

These rules apply regardless of which file you're editing. Internalize them
before opening any reference.

1. **Wrap multi-step state changes in a transaction.** Any action that
   creates a record AND tracks an event AND/OR touches associations must
   live inside `transaction do … end`. Half-applied state is the worst
   kind of bug.

2. **Async work follows _now/_later.** The synchronous version is the
   bare verb (`notify_recipients`, `process`, `deliver`). The async wrapper
   appends `_later` and only enqueues a job. The job's `perform` is one
   line that calls the sync method back. Never put logic inside `perform`.

3. **Multi-tenancy is automatic via `Current`.** Lambda defaults
   (`belongs_to :account, default: -> { board.account }`) and the
   `ActiveJob` extension that captures `Current.account` mean you should
   not pass `account:` to constructors, scopes, or jobs. If you find
   yourself doing that, you're fighting the framework.

4. **In tests, set `Current.session` in setup.** Lambda defaults like
   `default: -> { Current.user }` fail with `nil` unless a session is
   active: `setup { Current.session = sessions(:david) }`.

5. **Prefer expanded conditionals over guard clauses** (with one exception
   for top-of-method early returns guarding long bodies). See
   `references/code-style.md` for the rule and its exception.

6. **Names should reveal intent in domain language.** `gild`/`ungild`,
   `close`/`reopen`, `postpone`/`resume` — not `process`, `update_state`,
   `set_golden_flag`. Boolean methods always come in `foo?`/`not_foo?`
   pairs when both halves are meaningful.

## Routing table — load the relevant reference

The references are small, focused files. Load only the one(s) you need
right now; you don't have to read them all at once.

| If you're touching… | Read |
|---|---|
| Anything in `app/models/`, a new concern, a presenter | `references/models.md` |
| Anything in `app/controllers/` or `config/routes.rb` | `references/controllers.md` |
| Anything in `app/jobs/` or adding any async work | `references/jobs.md` |
| Anything in `test/` | `references/testing.md` |
| Adding a new state, event tracking, or background job (multi-file) | `references/recipes.md` |
| You want a quick check on Ruby style (method order, conditionals, etc.) | `references/code-style.md` |

CSS work belongs to a separate skill (`modern-css`); routes/views for
agent-domain rules live in the always-loaded `agents.md`.

## Anti-pattern checklist — run before finishing

After any non-trivial edit, scan the diff against this list. If any item
is true, fix it before moving on.

- [ ] **Custom action route** added (`post :close` instead of
      `resource :closure`). → Convert to RESTful resource.
- [ ] **Controller action longer than ~5 lines**, or contains logic beyond
      "load → call one model method → respond". → Move logic to the model.
- [ ] **Job `perform` longer than 3 lines** or contains business logic. →
      Move logic into a `_now`/sync method on the model; job calls that.
- [ ] **Callback contains business logic** (more than a touch, an
      increment, or an `_later` enqueue). → Move to an explicit method,
      call it from the controller.
- [ ] **`Event.create!(...)` written by hand** instead of `track_event`. →
      Use `track_event :action_name, particulars: { … }` inside the
      transaction.
- [ ] **`belongs_to :account` written without a lambda default** when an
      obvious parent provides it. → `default: -> { board.account }`.
- [ ] **Account explicitly passed to a job** (`SomeJob.perform_later(rec,
      account: …)`). → Drop it; `Current.account` is captured automatically.
- [ ] **Test missing `Current.session = sessions(:…)`** but exercises code
      that touches `Current.user` or lambda defaults. → Add it to `setup`.
- [ ] **Guard clause used where an expanded `if/else` would be just as
      readable.** → Prefer the expanded form, except when guarding a long
      method body at the top.
- [ ] **`!` on a method that has no non-bang counterpart**. → Remove `!`;
      it's only for sibling pairs like `save`/`save!`.

## When to push back

If a request asks for an anti-pattern (e.g. "add a `POST /tasks/:id/pause`
route"), name the idiomatic alternative briefly and proceed with it
(`resource :pause` under `tasks`). If the user insists on the
non-idiomatic version, follow their instruction — but note in the
response that you're deviating from the project pattern.

## Source of truth

The full prose, history, and examples live in
`docs/patterns-and-best-practices.md`. This skill is the compressed
working version; if a reference seems to contradict the source doc, the
source doc wins and the reference should be updated.
