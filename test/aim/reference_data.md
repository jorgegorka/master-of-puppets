# AIM Reference Data — Answer Key

This document describes the seed data and expected behaviors. Use it to judge whether a scenario response is correct.

---

## Seed Data

### Project
- **Name:** AIM Test Project

### Role Hierarchy

```
AIM CEO (Orchestrator) — root, budget $2000/mo
  ├── AIM VP Engineering (Orchestrator) — budget $1000/mo
  │     ├── AIM Senior Dev (Executor) — budget $500/mo
  │     └── AIM QA Engineer (Executor) — budget $500/mo
  └── AIM VP Strategy (Executor) — budget $500/mo
        └── AIM Research Analyst (Executor) — budget $250/mo
```

All roles use `claude_local` adapter with `claude-sonnet-4-20250514`.

### Missions (root tasks)

| Title | Assignee | Purpose |
|-------|----------|---------|
| AIM: Build MVP Feature | — (creator: CEO) | Parent of the subtasks below. Not targeted by any scenario directly. |
| AIM: Launch onboarding redesign | CEO | Empty root mission for `orch_delegates_goal` — CEO must delegate via `create_task`. |
| AIM: Implement payments module | VP Engineering | Empty root mission for `orch_delegates_only` — VP Eng must delegate via `create_task`. |

### Subtasks (children of "AIM: Build MVP Feature")

| Title | Status | Creator | Assignee | Scenario |
|-------|--------|---------|----------|----------|
| AIM: Write authentication module | pending_review | VP Engineering | Senior Dev | orch_reviews_task |
| AIM: Write API documentation | in_progress | VP Engineering | Senior Dev | executor_writes_documentation, executor_incorporates_approval_feedback |
| AIM: Analyze competitor pricing models | in_progress | CEO | VP Strategy | executor_compares_competitors |
| AIM: Build entire platform from scratch | in_progress | VP Engineering | Senior Dev | executor_flags_oversized_work |
| AIM: Write test plan for authentication | in_progress | VP Engineering | QA Engineer | executor_writes_test_plan |
| AIM: Integrate payment gateway | in_progress | VP Engineering | Senior Dev | executor_flags_blocker |
| AIM: Compile list of enterprise AI platforms | in_progress | VP Strategy | Research Analyst | executor_stays_on_task |
| AIM: Comprehensive market analysis | in_progress | CEO | VP Strategy | executor_delegates_parallelizable_research |
| AIM: SWOT analysis of current product | in_progress | CEO | VP Strategy | executor_writes_swot |
| AIM: Pricing strategy recommendation | in_progress | CEO | VP Strategy | executor_mixed_complexity |
| AIM: Write executive brief on AI market trends | in_progress | CEO | VP Strategy | executor_writes_brief |
| AIM: Summarize SaaS pricing tiers | in_progress | CEO | VP Strategy | executor_filesystem_prohibited |
| AIM: Post pricing analysis on root mission | in_progress | CEO | VP Strategy | executor_escalates_permission_error |
| AIM: Q2 strategic market assessment | pending_review | CEO | VP Strategy | orch_no_self_review |

Every scenario has its own dedicated task — no sharing between scenarios (with one exception: `executor_writes_documentation` and `executor_incorporates_approval_feedback` both target "AIM: Write API documentation"; the latter activates only when the prompt carries a "## Human Feedback" block).

The "Write authentication module" task has a message from Senior Dev: "Implemented authentication with bcrypt password hashing, session tokens, and login/logout endpoints. All unit tests pass."

The "Q2 strategic market assessment" task has a message from VP Strategy: "Completed the Q2 strategic market assessment. Key findings: agent orchestration demand is accelerating, governance features are a differentiator, and our pricing should follow a hybrid model."

---

## Expected Behaviors by Category

### Orchestrator

**Must do:**
- Delegate work via `create_task` specialist
- Hand off reviews to `review_task` specialist
- Post rolled-up summaries via `add_message`

**Must NOT do:**
- Produce deliverables directly (no writing code, docs, or analysis)
- Read task details and make review decisions itself (review_task specialist owns that)
- Call `update_task_status` with `completed` or `open` (only the review specialist does this)

### Executor

**Must do:**
- Do work directly by default and post deliverables via `add_message`
- Submit for review via `update_task_status("pending_review")` when there are no subtasks
- Flag oversized non-parallelizable work via `add_message`, then stop
- Flag blockers/missing dependencies via `add_message`, then stop
- Acknowledge `## Human Feedback` via `add_message` *before* doing any other work

**May do (rare path):**
- Delegate parallelizable data-gathering to direct reports via `create_task` *only* when ALL of: (a) multiple genuinely independent streams, (b) a report has the relevant capability, (c) parallel execution meaningfully speeds the work. Single-response deliverables (briefs, comparison tables, SWOT, one-pagers) MUST NEVER be delegated.

**Must NOT do:**
- Delegate work that it should do directly (simple, single-response tasks)
- Mark own tasks `completed` (only the reviewer can)
- Produce speculative work when blocked (implementation plans, workarounds)
- Fall back to filesystem tools (Read/Write/Glob/Grep/Bash/Edit) instead of `add_message` to deliver
- Silently reroute on permission errors — must flag the blocker on its own task and stop

---

## Per-Scenario Expected Tool Calls

| Scenario | Expected Tools | Forbidden Tools | Key Judgment |
|----------|---------------|-----------------|--------------|
| orch_delegates_goal | create_task | update_task_status | CEO receives an empty mission ("Launch onboarding redesign") — must delegate |
| orch_reviews_task | review_task | get_task_details, update_task_status | Should hand off to specialist, not self-review |
| orch_delegates_only | create_task | update_task_status, review_task | VP Eng receives an empty mission ("Implement payments module") — must delegate |
| orch_no_self_review | review_task | get_task_details, update_task_status | CEO hands off review to specialist |
| orch_search_discipline | create_task | (search_documents ≤1 call) | CEO must not spam search before delegating |
| orch_checks_delegation_feasibility | create_task | — | Cross-task posting must stay in orchestrator's own session, not embedded in subtask intent |
| executor_writes_documentation | add_message, update_task_status | create_task, hire_role | Single-response writing task — do it yourself |
| executor_compares_competitors | add_message, update_task_status | create_task, hire_role | 3-competitor comparison fits in one response — no delegation |
| executor_writes_swot | add_message, update_task_status | create_task, hire_role | One-page SWOT — own it entirely |
| executor_writes_brief | add_message, update_task_status | create_task, hire_role | Simple writing task — full work-then-submit cycle |
| executor_writes_test_plan | add_message, update_task_status | create_task, hire_role | QA Engineer produces work and submits |
| executor_stays_on_task | add_message, update_task_status | create_task, hire_role | Should stay on assigned task, produce work, submit |
| executor_flags_oversized_work | add_message | create_task, hire_role, update_task_status | Cross-functional engineering work is not parallelizable research — flag and stop |
| executor_flags_blocker | add_message | create_task, hire_role, update_task_status | Missing API keys — flag blocker and stop |
| executor_delegates_parallelizable_research | create_task *or* add_message+update_task_status | — | Multiple independent research streams — may delegate; doing it directly also acceptable |
| executor_mixed_complexity | add_message, create_task | — | Part 1 direct, Part 2 delegated |
| executor_filesystem_prohibited | add_message, update_task_status | Glob, Read, Grep, Bash, Write, Edit | Synthesize from brief; flag gaps inline |
| executor_escalates_permission_error | add_message | update_task_status | Cross-task post denied — flag blocker on own task, do NOT submit |
| executor_incorporates_approval_feedback | add_message, update_task_status | create_task, hire_role | Acknowledge `## Human Feedback` first, then revise and submit |
