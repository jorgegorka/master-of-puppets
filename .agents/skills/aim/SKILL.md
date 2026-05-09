---
name: aim
description: AIM (AI Improver) — Diagnose and optimize Director role category job specs. Use when running diagnostics, analyzing agent behavior, optimizing prompts, or managing test scenarios.
---

# AIM — AI Improver

You are operating AIM, a system for diagnosing and improving Director's AI agent behavior. Director agents use role category job specs (Orchestrator, Planner, Worker) to determine how they approach work — delegation, direct execution, or planning. The job specs are system prompts delivered via `ClaudeLocalAdapter.compose_system_prompt`.

Your job is to help the developer run scenarios against the agents, analyze whether they follow their job specs correctly, and iteratively improve the prompts.

---

## Files

```
test/aim/
  scenarios.yml             # Test scenarios with expected behaviors
  reference_data.md         # Known data — the "answer key" for evaluating responses
  architecture.md           # Prompt pipeline reference — read when analyzing or optimizing
  lib/runner.rb             # Execution engine
  results/
    raw/                    # JSON from rake task (ephemeral)
    diagnostics/            # Final diagnostic reports in MD (persistent)
```

---

## Modes

Adapt your behavior based on what the developer asks:

**Discussion** — The developer wants to reason about strategy, review past diagnostics, or plan what to test next. Don't execute anything. Talk.

**Diagnostic** — The developer wants to run scenarios and get an analysis. Execute the rake task, read the results, analyze against reference_data.md, and write a diagnostic report.

**Optimization** — The developer wants to improve a specific part of the prompt through iterative testing. This is the loop: run scenarios, analyze, propose a change, apply it, re-run, compare, repeat. Read `test/aim/architecture.md` before starting — you need to know what files to modify and how the system works.

**Dataset** — The developer wants to create or modify scenarios. Read `test/aim/scenarios.yml` to understand the format and existing scenarios, then propose new ones.

---

## Running scenarios

### Prerequisites
- Rails server running (`bin/dev` in another terminal)
- Seed executed at least once (`bundle exec rake aim:seed`)
- Codex CLI authenticated and available in PATH

### Command
```bash
bundle exec rake aim:run SCENARIOS=id1,id2,id3
bundle exec rake aim:run SCENARIOS=all
```

### Selecting scenarios
When the developer describes what they want to test ("orchestrator delegation", "worker scope discipline", "all planner scenarios"), read `test/aim/scenarios.yml`, filter by the relevant tags/category, and present the selected IDs. Always confirm before executing.

### Output
Results are written to `test/aim/results/raw/{timestamp}.json`. Each scenario includes:
- `scenario_id`, `status` (success/error), `role_title`, `category`
- `tool_calls`: array of `{tool, params}` — what tools the agent called
- `response`: the full text response from the agent
- `cost_cents`, `duration_seconds`
- `error`: error message if status is "error"

---

## Analyzing results

After execution, read the JSON results, `test/aim/reference_data.md`, and `test/aim/scenarios.yml`. For each scenario:

1. **Were the expected tools called?** Check `tool_calls` against the scenario's `expected_tools`. Every expected tool should appear at least once.
2. **Were forbidden tools avoided?** Check `tool_calls` against `forbidden_tools`. None should appear.
3. **Did the agent follow its category's job spec?**
   - Orchestrator: delegated, didn't produce deliverables
   - Worker: did work directly, didn't delegate
   - Planner: appropriate judgment on direct work vs delegation
4. **Quality**: Was the tool usage efficient? Appropriate parameters? Was the response coherent?
5. **Issues**: Note anything wrong — wrong tools, scope violations, unnecessary tool calls, hallucinated data.

Don't repeat identical analysis for every scenario. If tool selection is correct across all scenarios, say that once. Focus on what's interesting or broken.

### Diagnostic report
Always save the final diagnostic to `test/aim/results/diagnostics/{timestamp}.md` using the same timestamp as the raw results file.

**Structure:**
1. **Summary** — scenarios count, pass/fail, cost, duration
2. **Per-scenario detail** — for EVERY scenario, include:
   - The scenario description (category, trigger type)
   - Tools called with parameters
   - The agent response (full text, in a code block)
   - Expected vs actual tool usage
   - Verdict and analysis
3. **Issues** — grouped by severity with root cause analysis
4. **Recommendations** — prioritized actions

**The per-scenario detail is the most important part.** The developer needs to see the actual agent behavior to judge quality. Never summarize or omit the response text. Example format:

```markdown
### orch_delegates_goal — PASS

**Category:** Orchestrator | **Trigger:** goal_assigned | **Role:** AIM CEO
**Tools:** create_task({intent: "Implement user authentication...", goal_id: 1, parent_task_id: nil})

**Response:**
> I've delegated the authentication work to VP Engineering via a new task.
> Task #4 has been created and assigned.

**Analysis:** Correct delegation behavior. Used create_task specialist as expected.
Did not attempt to do work directly. Intent was well-scoped.
Expected: [create_task] | Actual: [create_task] | Forbidden: [update_task_status] — none used.
```

---

## Optimization loop

When the developer wants to improve something specific:

1. **Read `test/aim/architecture.md`** — understand where the prompts live
2. **Run the relevant scenarios** — establish a baseline
3. **Analyze what's failing and why**
4. **Propose ONE atomic change** — one section of the job spec, or one part of the identity prompt. Explain what you're changing and why.
5. **Apply the change** (edit the file)
6. **If editing `db/seeds/role_categories.yml`**, remind the developer to run `bin/rails db:seed` to reload the job specs into the database
7. **Re-run the same scenarios**
8. **Compare**: did it improve? Stay the same? Get worse?
   - Better: keep the change, continue to next iteration
   - Worse: revert (`git checkout` the file), try a different approach
   - Same: keep if it simplifies, otherwise discard
9. **Repeat** (max 5-7 iterations, or stop if no improvement in 2 consecutive iterations)
10. **Run ALL scenarios** at the end to check for regressions
11. **Write the final diagnostic** with the full change history and impact analysis

The developer reviews and decides whether to keep the changes. You never push or merge.

---

## Creating scenarios

Scenarios live in `test/aim/scenarios.yml`. Format:

```yaml
- id: short_descriptive_id        # Required, unique
  category: orchestrator           # orchestrator, planner, worker
  role_title: "AIM CEO"           # Must match a seeded role title
  trigger_type: task_assigned      # goal_assigned, task_assigned, task_pending_review
  context:                         # Fields fed to build_user_prompt
    task_title: 'The task title'
    task_description: 'What to do'
    goal_title: 'The goal title'   # For goal_assigned triggers
    assignee_role_title: 'Name'    # For task_pending_review triggers
  expected_tools: [add_message]    # Tools that MUST appear in the output
  forbidden_tools: [create_task]   # Tools that must NOT appear
  tags: [scope_discipline]         # Free-form tags for filtering
  reference: 'Expected behavior'   # What the correct response should contain/do
```

When creating scenarios, always add the `reference` field with enough detail that anyone (human or AI) can judge if the behavior is correct.

### Context field mapping

The `context` hash maps to `ClaudeLocalAdapter.build_user_prompt` input:

| Context field | Used for | Notes |
|--------------|----------|-------|
| `task_title` | Task lookup in seed data | Must match a seeded task title (partial match) |
| `task_description` | Overrides task description | Useful for custom scenarios |
| `goal_title` | Goal lookup in seed data | Must match a seeded goal title |
| `assignee_role_title` | Shown in review trigger prompt | Who submitted the work |

---

## Key rules

- Always confirm with the developer before executing scenarios
- Never push changes to git — the developer decides when to commit
- The diagnostic report is always the final deliverable
- During optimization, changes are temporary until the developer approves
- Estimate the number of API calls before executing ("this will run 4 scenarios, ~4 Codex calls, ~$0.12")
- After editing `db/seeds/role_categories.yml`, always remind about `bin/rails db:seed`
