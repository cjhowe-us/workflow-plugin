---
in_flight: []
---

# In-Flight Background Tasks

Sparse registry of **background** `Agent(run_in_background: true)` tasks. **Do not** mirror full
agent trees here — only enough to dedupe dispatches and reconcile completions.

Sub-skills use this file with **`locks.md`** (worktree claims) when stopping background work before
interactive work.

## Entry schema

```yaml
in_flight:
  - task_id: {Claude Code task id}
    worker_agent: {orchestrator or worker name}
    phase: {specify | design | plan | review | release}
    subsystem: {subsystem or all}
    plan_id: {PLAN-* when applicable}
    pr_number: {optional}
    started_at: {ISO 8601 UTC}
    last_seen: {ISO 8601 UTC — update in in-flight only; do not touch phase rollups for this}
```

## Reconciliation loop

1. Read this file
2. For each entry, check whether `task_id` is still running (host task APIs when available)
3. If **completed**, read output, apply **material** updates to phase/plan progress, **remove** row
4. If **stopped** / **error**, **remove** row; log only when something actionable changed
5. If **still running**, update **`last_seen`** in this file **only**

## Stop-before-lock protocol

When an interactive sub-skill claims a worktree in **`locks.md`**:

1. Read this file
2. **`TaskStop`** rows whose **`phase` / `subsystem` / `plan_id`** overlap the new lock (and any
   row whose plan’s **`branch`** matches the lock’s **`branch`** when known)
3. Remove those entries
4. Append the lock row to **`locks.md`**

Background workers **must** skip work that conflicts with **`locks.md`** (see harmonize skill).
