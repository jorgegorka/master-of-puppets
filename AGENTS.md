# AGENTS.md

This file provides guidance to Agents when working with code in this repository.

## What This Is

Master of Puppets is a Rails 8 orchestration platform for AI agent projects. Users create projects staffed by AI agents, organize them in hierarchies, assign tasks (root tasks act as missions), enforce budgets, and govern operations through approval gates.

## Hard Constraints

- **Auth**: Rails 8 built-in authentication (`has_secure_password` + `bin/rails generate authentication`) — NO Devise
- **Frontend**: Hotwire (Turbo + Stimulus) + modern CSS — NO Tailwind, NO React
- **CSS**: Pure custom CSS with OKLCH colors, CSS layers, logical properties — see `docs/style-guide.md`
- **Testing**: Minitest + fixtures — NO RSpec, NO FactoryBot, NO system/integration tests
- **Multi-tenancy**: `Current.project` scoping — NO acts_as_tenant gem
- **Database**: SQLite for everything (primary + Solid Queue/Cache/Cable)
- **Deployment**: Kamal + Docker

## Commands

```bash
bin/setup              # Install deps, prepare DB, start server
bin/dev                # Start dev server
bin/ci                 # Full CI suite (rubocop → security → tests)

# Testing (unit + controller tests only — no system/integration tests)
bin/rails test                              # All tests
bin/rails test test/models/user_test.rb     # Single file
bin/rails test test/models/user_test.rb:25  # Single test by line

# Linting
bin/rubocop            # Style check (rubocop-rails-omakase)
bin/rubocop -a         # Auto-fix

# Security
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

## Architecture

Ruby on Rails 8 app.

## Conventions

- **CSS architecture**: See `docs/style-guide.md` — CSS layers, OKLCH color system, semantic variables, logical properties, dark mode support, icon system via CSS masks
- **Rails patterns**: See `docs/patterns-and-best-practices.md` — concern architecture (shared + model-specific), intention-revealing APIs, thin controllers, `_now`/`_later` job pattern
- **RESTful controllers, no custom verbs**: Model state transitions as nested resources with standard CRUD actions — never custom controller actions. To start/stop a role's activity, create `Roles::ActivitiesController` with `create`/`destroy`, not `start`/`stop` actions on `RolesController`. See `docs/patterns-and-best-practices.md` § 4.2.
- **Business logic in models, concerns past 2 methods**: Business logic lives on models, but extract to a namespaced model-specific concern (e.g. `Roles::Hiring` in `app/models/roles/hiring.rb`) as soon as more than 2 related methods accumulate, so models stay short. See `docs/patterns-and-best-practices.md` § 2.1.
- **Plain Ruby first, ActiveModel when needed**: New classes that handle logic start as plain Ruby objects (PORO). Reach for [ActiveModel modules](https://guides.rubyonrails.org/active_model_basics.html) — `Attributes`, `Validations`, `Callbacks`, `Model`, etc. — only when the class actually needs that behavior. Do not subclass `ApplicationRecord` or invent ad-hoc validation/attribute code when `include ActiveModel::Model` (or a specific module) already provides it.
