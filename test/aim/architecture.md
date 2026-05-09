# Director AI Architecture — AIM Reference

This document maps the Director prompt composition pipeline. Read it when you need to understand or modify agent behavior.

---

## How an agent runs

```
Task assigned or pending review (or heartbeat)
  → ExecuteRoleJob enqueued
    → Builds context hash (task, root_task, skills, documents)
    → ClaudeLocalAdapter.execute(role, context)
      → compose_system_prompt(role, context)
        → build_identity_prompt (who you are, org chart, tool catalog)
        → role.job_spec (role-specific override, if any)
        → role.role_category.job_spec (category behavioral instructions)
        → build_root_task_prompt (if the task is a subtask of a root mission)
        → build_skills_prompt (if role has skills)
      → build_user_prompt(context)
        → Task assigned: task title + description + documents (+ active_subtasks if root)
        → Task pending review: task id + assignee + hand-off instruction
        → Heartbeat (no task_id): "Check your assigned tasks"
      → Spawns `claude -p` in tmux with stream-json output
      → MCP config points at bin/director-mcp with role's API token
```

Root tasks (missions) are just `Task` records with `parent_task_id IS NULL`. There is no separate Goal model — `Task.roots` / `task.root?` / `task.root_ancestor` identify missions.

---

## System prompt composition

**File:** `app/adapters/claude_local_adapter.rb`

The system prompt is composed from 5 parts in this order:

| Part | Method | Lines | Content |
|------|--------|-------|---------|
| Identity | `build_identity_prompt` | 190-239 | Role title, project name, org chart (manager + reports), specialist tool catalog, efficiency rules |
| Role job_spec | `role.job_spec` | — | Optional role-level override (most roles don't have one) |
| Category job_spec | `role.role_category.job_spec` | — | The main behavioral instructions — Orchestrator or Executor |
| Mission context | `build_root_task_prompt` | 241-253 | Only included for subtasks. Shows root task title + description + focus rules. Root tasks themselves don't get this block. |
| Skills | `build_skills_prompt` | 255-277 | Skill catalog + full markdown instructions |

---

## User prompt (trigger context)

**File:** `app/adapters/claude_local_adapter.rb:279-310`

The user prompt branches on trigger type and task shape:

| Trigger | What the agent sees |
|---------|--------------------|
| `task_pending_review` | "Task #N is pending your review: {title}. {assignee} has submitted this task for review. Hand this off to the review_task specialist — do not read the task and decide yourself." |
| `task_assigned` (subtask) | "You have been assigned Task #N: {title}. {description}. Reference documents (if any). Start working immediately. When finished: post deliverables via add_message, then update_task_status(pending_review)." |
| `task_assigned` (root task with active subtasks) | Same as above, plus an "Active Subtasks" list and an instruction: "Focus on completing the existing subtasks above — do NOT create new subtasks unless all current ones are completed or blocked and more work is clearly needed." |
| `task_assigned` (root task with no subtasks) | Same as the subtask form — orchestrators should delegate via `create_task`. |
| No `task_id` (heartbeat) | "Check your assigned tasks with list_my_tasks, then execute the highest-priority work." |

---

## Files to modify during optimization

### High impact (affects all roles in a category)

| File | What it controls |
|------|-----------------|
| `db/seeds/role_categories.yml` | The 2 category job specs (Orchestrator, Executor). Primary optimization target. After editing, run `bin/rails db:seed` to reload into the database. |

### Medium impact (affects all roles)

| File | What it controls |
|------|-----------------|
| `app/adapters/claude_local_adapter.rb:190-239` | Identity prompt — shared "How to Work" section, specialist tool descriptions, efficiency rules. |
| `app/adapters/claude_local_adapter.rb:279-310` | User prompt — how tasks are presented. Controls context quality. |
| `app/adapters/claude_local_adapter.rb:241-253` | Mission context — inserted into system prompt when executing a subtask. |

### Medium impact (affects specific sub-agents)

| File | What it controls |
|------|-----------------|
| `app/mcp/sub_agents/create_task.rb` | create_task specialist system prompt |
| `app/mcp/sub_agents/review_task.rb` | review_task specialist system prompt |
| `app/mcp/sub_agents/hire_role.rb` | hire_role specialist system prompt |
| `app/mcp/sub_agents/summarize_task.rb` | summarize_task specialist system prompt |

### Low impact (affects tool descriptions)

| File | What it controls |
|------|-----------------|
| `app/mcp/tools/*.rb` | Individual tool definitions — tool name, description, input schema |
| `app/mcp/director_server.rb:9-45` | Tool scopes — which tools each category/sub-agent can see |

---

## Tool scopes

Defined in `app/mcp/director_server.rb:9-45` as `TOOL_SCOPES`. Every role currently runs under the `:orchestrator` scope — orchestrator/executor differentiation comes entirely from the job_spec prompt, not from the tool whitelist.

### `:orchestrator` scope (11 tools)

**Specialist wrappers** (spawn sub-agents):
- `create_task_agent` → wraps `Tools::CreateTaskAgent`
- `review_task_agent` → wraps `Tools::ReviewTaskAgent`
- `hire_role_agent` → wraps `Tools::HireRoleAgent`
- `summarize_task_agent` → wraps `Tools::SummarizeTaskAgent`

**Mechanical tools** (direct use):
- `update_task_status`, `list_my_tasks`
- `list_available_roles`, `list_hirable_roles`
- `add_message`, `get_task_details`
- `search_documents`, `get_document`

### Sub-agent scopes

| Sub-agent | Tools |
|-----------|-------|
| `sub_agent_create_task` | `get_task_details`, `list_available_roles`, `create_task` (direct mutation) |
| `sub_agent_review_task` | `get_task_details`, `submit_review_decision` |
| `sub_agent_hire_role` | `list_hirable_roles`, `hire_role` (direct mutation) |
| `sub_agent_summarize_task` | `get_task_details`, `update_task_summary` (direct mutation) |

**Note on executor discipline:** Both categories currently share the orchestrator tool scope at the `DirectorServer` level. Behavioral discipline (executors not over-delegating, orchestrators not producing deliverables) comes entirely from the job_spec prompt instructions. This is a known design gap.

---

## Configuration

| Setting | Value | Where |
|---------|-------|-------|
| Default model | claude-sonnet-4-20250514 | `db/seeds.rb:27` (also in `test/aim/seed.rake`) |
| Max turns (sub-agents) | 8 | `app/mcp/sub_agents/base.rb:8` (`DEFAULT_MAX_TURNS`) |
| Max turns (AIM scenarios) | 10 | `test/aim/lib/runner.rb:13` (`DEFAULT_MAX_TURNS`) |
| MCP transport | stdin/stdout JSON-RPC | `app/mcp/director_server.rb` |

---

## Context building (for AIM scenarios)

The AIM runner (`test/aim/lib/runner.rb#build_context`) must replicate the context hash that `ExecuteRoleJob#build_context` produces. The shape depends on whether the triggering task is a root mission or a subtask:

```ruby
# Common fields
{
  trigger_type: "task_assigned",        # or "task_pending_review"
  task_id: task.id,
  task_title: task.title,
  task_description: task.description,
  assignee_role_title: task.assignee&.title,
  skills: [...]
}

# If task.root? (a mission) AND it has active subtasks:
{
  active_subtasks: [
    { id:, title:, status:, assignee_id: },
    ...
  ]
}

# If task is a subtask (not root):
{
  root_task_id: root.id,
  root_task_title: root.title,
  root_task_description: root.description
}
```

Mission scenarios — where an orchestrator should delegate — must point at a root task that has **no active subtasks** (otherwise `build_user_prompt` tells the orchestrator not to create new ones). The AIM seed (`test/aim/seed.rake`) reserves two empty missions specifically for this: `AIM: Launch onboarding redesign` (CEO) and `AIM: Implement payments module` (VP Engineering).

---

## Harness invariant: per-scenario subtask cleanup

Before every scenario, the runner destroys all subtasks of the scenario's target task (`test/aim/lib/runner.rb:36-50`). This prevents state pollution across runs:

- A prior run of an orchestrator scenario may have successfully delegated and left live subtasks on the target task.
- The next run sees `active_subtasks` populated in the user prompt, which correctly tells the orchestrator "focus on completing existing subtasks — do NOT create new ones".
- The second scenario then appears to fail ("orchestrator didn't delegate") when in reality the orchestrator was following instructions against a polluted state.

The cleanup resets the target task to a freshly-assigned state: no subtasks, no `active_subtasks` key in the context hash. Scenarios that require active subtasks as input must recreate them inside the scenario body — do not rely on residue from earlier runs.

**When adding scenarios:** if a scenario needs a pre-existing subtask (e.g. to test review flows), seed it explicitly in `test/aim/seed.rake` under a task that is not the target of any delegation scenario — otherwise the cleanup will destroy it on every run. Reserved empty missions for delegation scenarios are listed in the "Context building" section above.
