# Master of Puppets

Open-source orchestration platform for AI agents. Define roles, assign work, enforce budgets, and keep humans in the loop — at any scale.

Managing multiple AI agents gets messy fast. They run in different tabs, lose context between sessions, burn through money with no oversight, and nobody knows what any of them are actually doing. Master of Puppets fixes this by giving you a structured orchestration layer — define roles in an org chart, assign AI agents to them through pluggable adapters (HTTP, CLI, Claude, OpenCode, Codex), and let them work autonomously within budgets, approval gates, and human oversight. It works for a solo developer automating a side project, a team running a single department, or a full organization with dozens of specialized agents.

<img width="969" height="661" alt="Direct a team of AI Agents" src="https://github.com/user-attachments/assets/ccdceb18-22cb-4fd8-b589-48e49b69dbe4" />

## Quick install

Run Master of Puppets on your own machine with **one command**:

```bash
curl -fsSL https://raw.githubusercontent.com/jorgegorka/master-of-puppets/master/scripts/install.sh | sh
```

The installer pulls the official Docker image and starts Master of Puppets at [http://localhost:3000](http://localhost:3000), with a persistent volume so your data survives restarts. On Linux it installs Docker for you if it isn't already there; on macOS install [Docker Desktop](https://www.docker.com/products/docker-desktop) first. See [Install](#install) below for details and container management.

## How it works

### Projects and teams

Everything starts with a project. You create one, give it a name, and you become its owner. From there you can invite other people to join as members or admins. Each person can belong to multiple projects, and each project is completely isolated — its roles, tasks, budgets, and data are separate from the rest.

First-time users are walked through an **onboarding wizard** that sets up an initial project, picks a department template, and hires a top-level role — so you go from a fresh install to a working org chart in a couple of clicks.

If something goes wrong across the board, an admin can hit the **emergency stop** to freeze every active role in the project at once.

### Roles and org chart

Inside each project you define roles — CEO, lead engineer, content writer, support representative, whatever fits your operation. Roles are arranged in a hierarchy, just like a real org chart, with parent-child relationships that determine who reports to whom. Each role has a job specification describing what it's responsible for.

Every role belongs to one of two **categories** that determine how it behaves:

- **Orchestrator** — delegates work to direct reports, reviews results, and coordinates execution. Does not produce deliverables directly. Think CEO, department head, team lead.
- **Executor** — does the work directly and produces deliverables. May delegate parallelizable data-gathering to direct reports when warranted, but synthesis and the final output are always its own.

Each category comes with a structured job spec that defines the MCP protocol the role follows — which tools to use, in what order, and what quality standards to meet. This means roles don't just have different titles, they have fundamentally different behavior patterns.

A role starts as an empty position in the org chart. It becomes AI-powered when you **hire** into it — meaning you configure an adapter that connects it to an AI service. When a role is first hired, it automatically receives a default set of skills relevant to its position.

### Hiring and adapters

Hiring a role means connecting it to an AI service through one of five adapters:

- **HTTP** — sends tasks to any AI service via web requests. Master of Puppets posts a JSON payload to a URL you configure and handles the response, including automatic retries with increasing wait times if something fails.
- **Process** — runs a command-line program on the server. Useful for local scripts or CLI-based AI tools.
- **Claude Local** — launches a Claude session in a dedicated terminal window, streams the output in real time, and enforces budget limits before each run starts. You can configure a **working directory** so the role operates in the right project context, and pick **Anthropic or Ollama** as the provider to run local or hosted models.
- **OpenCode** — runs the OpenCode CLI locally in a dedicated tmux session, streams its JSON output into the run log, and enforces budget checks before execution. Supports a configurable working directory, model, and `max_turns`, and can target **Anthropic or Ollama** as the provider for fully local operation.
- **Codex** — runs the OpenAI Codex CLI locally in a dedicated tmux session, streams its JSON event log into the run view, and enforces budget checks before execution. Targets **OpenAI or Ollama** as the provider, resumes sessions across runs, and exposes per-role **sandbox** and **approval** policies to control filesystem writes and command execution.

Once hired, roles have a lifecycle you control directly. You can **pause** a role (with a reason), **resume** it, **terminate** it permanently, or **manually wake it up** to start working on demand. If a role tries to do something that requires approval, it enters a **pending approval** state until a human approves or rejects the action.

Each role has its own profile showing its assigned skills, linked documents, recent heartbeat activity, and a full history of its runs.

Roles can also **hire subordinate roles** from their department template. If `auto_hire` is enabled on the role, the hire happens instantly — a new child role is created with the same adapter configuration and the specified budget. If auto_hire is off, the hiring request creates a **pending hire** that must be approved by an admin. This means roles can organically grow their own teams within the boundaries of their department template.

### Role templates

Master of Puppets ships with **8 department templates** — Engineering, Finance, Legal, Marketing, People, Product, Sales, and Customer Success. Each template defines a complete team: a hierarchy of roles with titles, descriptions, job specs, and pre-assigned skills.

You can browse templates and **apply** one to your project. The applicator creates all the roles in the template that don't already exist, wires up the parent-child hierarchy, and assigns skills automatically. This gives you a fully staffed department in one click.

### Tasks

Tasks are the units of work in Master of Puppets. You create a task with a title, description, and priority level (low, medium, high, or urgent), then assign it to a role. Tasks live on a **Kanban board** where you can see them organized by status: open, in progress, blocked, completed, or cancelled.

Tasks support **delegation** — a role can hand off a task to another role — and **escalation**, where a task gets bumped up to the role's manager in the org chart. Both of these can be subject to approval gates if you want human oversight on those decisions. Roles can also **ask questions** to their manager on a task — the question is posted as a message, the manager is woken up to answer, and the asking role is notified when the answer arrives.

You can attach **documents** to tasks for reference material, and people or roles can post **messages** on tasks to discuss the work, with full threading support. Tasks can also have **subtasks** through parent-child relationships, so complex work can be broken into smaller pieces.

Every task tracks its cost, so you always know how much a piece of work actually cost to complete.

### Goals

Goals are how you direct your project at a high level. In Master of Puppets, a goal is simply a **root task** — a task with no parent — that describes what you want accomplished. Agents break it down into subtasks, and those subtasks drive the work forward. The `/goals` page lists every root task in the project so you can see each mission at a glance.

A root task carries the same fields as any other task: title, description, priority, assignee. As its subtasks get completed, the root task's completion percentage rolls up automatically. When every subtask reaches `completed`, the root task auto-completes and Master of Puppets runs a summarization step that writes a short achievement summary onto the root task.

When a subtask is approved, Master of Puppets automatically **evaluates** whether the work advances its root task's intent. An AI evaluator reviews the root task's description, the subtask, and the work output, then gives a **pass** or **fail** with feedback. If the evaluation fails, the subtask is reopened and the role is woken up with the feedback to try again. Each subtask gets up to **3 attempts** — if all are exhausted, the subtask is escalated to the **human review** queue. This creates an automatic quality feedback loop tied directly to each mission.

### Skills

Skills define what a role is capable of. Master of Puppets comes with **41 built-in skills** organized across 6 categories (technical, leadership, management, operations, research, creative), and you can create your own custom skills on top of that.

Each skill has a name, description, category, and detailed documentation written in markdown. You can attach reference documents to skills for additional context. Skills are managed at the project level and then assigned to individual roles — you pick which skills each role should have through a simple checkbox interface.

When a new project is created, it's automatically seeded with the full set of built-in skills. Built-in skills are protected and can't be deleted.

### Documents

Documents are the knowledge base of Master of Puppets. You create documents with a title and markdown content, organize them with **tags**, and link them to roles, tasks, or skills. This way the roles that need reference material have access to it.

Documents track who created them and who last edited them, so there's always accountability for the information in your knowledge base.

### Role hooks

Hooks let you automate workflows between roles. You attach hooks to a role and configure them to fire on lifecycle events — for example, **after a task starts** or **after a task completes**.

When a hook fires, it can do one of two things:

- **Trigger another role** — creates a subtask and wakes up a different role to handle it. When that role finishes, the result is posted back to the original task, and the first role is woken up to review it. This creates a **validation feedback loop** where roles check each other's work.
- **Call a webhook** — sends a JSON payload to an external URL with custom headers and timeout settings. This lets you integrate Master of Puppets with other systems — notifications, logging, external workflows, anything that accepts HTTP requests.

Each hook execution is tracked with its status, timing, and payload data, and hooks support automatic retries if something fails.

### Budgets

Every role can have a budget. Before a role starts a run, Master of Puppets checks whether the role can afford it — if the budget is exhausted, the run is blocked before it even begins.

Roles report their costs back to Master of Puppets as they work, and you can see per-role spending on the dashboard. The budget tracking is atomic, meaning costs are enforced precisely without race conditions even when multiple roles run simultaneously.

### Approval gates

Approval gates are how you keep humans in the loop. You configure them per role, choosing which actions require human approval before they can proceed:

- **Task creation** — role wants to create a new task
- **Task delegation** — role wants to hand off work to another role
- **Budget spend** — role wants to spend beyond a threshold
- **Status change** — role wants to change its own status
- **Escalation** — role wants to escalate an issue to its manager

When a role triggers a gate, it pauses and waits. An admin reviews the request and either **approves** or **rejects** it with a reason.

### Role runs

Every time a role executes a piece of work, Master of Puppets creates a **run record** that tracks the full lifecycle: queued, running, completed, failed, or cancelled. Each run captures the trigger that started it (heartbeat, task assignment, mention, etc.), the cost incurred, the exit code, and the complete log output.

For roles using the Claude Local adapter, you can **watch the output live** as it streams in real time — you see exactly what the role is thinking and doing. If a run is taking too long or going in the wrong direction, you can **cancel it** directly from the interface, which kills the underlying process immediately.

Runs are processed through a dedicated job queue, and roles can resume sessions across multiple runs for continuity.

<img width="1235" height="808" alt="Master of Puppets - AI Orchestrator" src="https://github.com/user-attachments/assets/6b21b084-a64d-4b20-991e-80587216292c" />


### Dashboard

The dashboard is your command center. At a glance you can see:

- How many roles are active and online
- Active and completed task counts
- Budget utilization across all roles with per-role spending breakdowns
- A Kanban view of all tasks grouped by status
- A real-time activity timeline showing what's happening across the project
- Mission progress across the project's root tasks
- An **approvals queue** that consolidates everything waiting for human action — gate-blocked roles, pending hires, and tasks pending review — in one place

The dashboard updates in real time — when a role completes a task, starts a run, or triggers a hook, you see it immediately without refreshing the page.

A persistent **collapsible sidebar** gives you one-click access to every section of the app — dashboard, roles, tasks, goals, documents, skills, approvals, and audit log — and remembers its open/closed state across sessions.

### Audit trail

Every significant action in Master of Puppets is recorded in an **immutable audit log** — it can't be edited or deleted. You can filter the log by who performed the action (user or role), what type of action it was, and when it happened.

On top of that, every change to a role's configuration is captured as a **config version**. You can view the full history of changes, compare any two versions to see exactly what changed, and **roll back** to a previous configuration if needed.

### Notifications

Master of Puppets notifies you when things need your attention — when you're mentioned in a task message, when a task is assigned to you, or when a role action requires your approval. Notifications are scoped to the project you're working in and can be marked as read.

### MCP tools

Master of Puppets exposes a suite of **MCP tools** to the orchestrator scope that roles use to interact with the system. These are the hands and eyes of every AI role — the only way they can read tasks, post results, delegate work, or access documents.

The tools cover four areas: **task management** (create, update status, list, and inspect tasks — including root tasks as missions), **review and summarization** (review completed subtasks, summarize completed missions), **role coordination** (list available roles, hire subordinates, post messages), and **document access** (search and read reference material). Each role category's job spec defines which tools to use and in what order, so orchestrators delegate via `create_task` while executors execute and report via `add_message` (and may delegate parallelizable research via `create_task` when warranted).

Communication with roles uses JSON-RPC 2.0 over stdin/stdout, so any process that speaks that protocol can act as an AI backend.

## Who is Master of Puppets for?

- **Anyone orchestrating multiple AI agents** — whether it's a full AI-powered organization, a single department, or a weekend project. You need structure, budgets, and oversight instead of tab chaos.
- **Teams adding AI to existing workflows** — you want guardrails and visibility before trusting agents with real work, plus approval gates to keep humans in the loop.
- **Developers who want self-hostable infrastructure** — you need orchestration you can customize and own, not a SaaS dependency. Master of Puppets is open source, runs on SQLite, and deploys anywhere.

## Tech stack

- Ruby on Rails 8.1
- SQLite for everything (one file, no database server to install)
- Hotwire for real-time updates without JavaScript frameworks
- Custom CSS (no Tailwind, no Bootstrap)
- Docker-ready for deployment

## Install

The one-command installer (see [Quick install](#quick-install) at the top) is the recommended path. Under the hood it:

- Detects your OS and architecture, installing Docker on Linux if missing (on macOS you install [Docker Desktop](https://www.docker.com/products/docker-desktop) first).
- Pulls the latest Master of Puppets image from GHCR (`ghcr.io/jorgegorka/master-of-puppets:latest`).
- Runs it as a container named `master-of-puppets` on port `3000`, with a persistent `master_of_puppets_storage` volume for your SQLite data.

```bash
curl -fsSL https://raw.githubusercontent.com/jorgegorka/master-of-puppets/master/scripts/install.sh | sh
```

Then visit [http://localhost:3000](http://localhost:3000). Data persists in the `master_of_puppets_storage` Docker volume across restarts, and you can override the image, container name, volume, or host port with the `MASTER_OF_PUPPETS_IMAGE`, `MASTER_OF_PUPPETS_CONTAINER`, `MASTER_OF_PUPPETS_VOLUME`, and `MASTER_OF_PUPPETS_PORT` environment variables.

Manage the container with the usual Docker commands:

```bash
docker logs -f master-of-puppets
docker stop master-of-puppets
docker start master-of-puppets
```

## Develop

Contributing to Master of Puppets? Clone the repo and run it natively. You need Ruby 3.4. No Node.js or external database required.

```bash
git clone https://github.com/jorgegorka/master-of-puppets.git
cd master-of-puppets
bin/setup
bin/dev
```

Then visit [http://localhost:3000](http://localhost:3000).

# Contributors

- [Mario Alvarez](https://github.com/marioalna)
- [Jorge Alvarez](https://github.com/jorgegorka)

## License

Released under the [MIT License](LICENSE).
