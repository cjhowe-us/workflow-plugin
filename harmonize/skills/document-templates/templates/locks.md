---
locks: []
---

# Worktree locks

Each row describes **one checkout’s purpose** — typically the **branch** and **worktree path** Git
knows about, plus a **single-line `reason`** stating what that worktree is doing right now.

**Together, all rows are the lightweight snapshot of who owns which tree for what** (interactive
sessions, explicit holds, or rare manual entries). They are **not** a full agent tree and should not
be updated on every orchestrator tick.

For **abandoned-work resume**, trust **`git worktree list`**, **`PLAN-*` progress** (`branch`,
`worktree_path`, `status`), and this file — not separate agent-tree registries.

## Entry schema

```yaml
locks:
  - branch: main                    # branch checked out in this worktree (required)
    worktree_path: /abs/path       # path from `git worktree list`; use primary repo root for main
    phase: plan                    # specify | design | plan | review | release
    subsystem: core-runtime        # scope — docs/plans/<subsystem>/...
    plan_id: PLAN-core-runtime-foo # optional; set when work is for one plan
    claimed_at: {ISO 8601 UTC}
    owner: harmonize-plan          # sub-skill or session owner
    reason: User stepping through ECS plan on main  # one line: what this worktree is doing
```

**`reason`** must stay short — it is the human-readable summary of that worktree’s job.

## Examples

```yaml
locks:
  - branch: main
    worktree_path: /Users/me/Code/harmonius
    phase: plan
    subsystem: core-runtime
    plan_id: null
    claimed_at: 2026-04-13T15:30:00Z
    owner: harmonize-plan
    reason: Interactive plan authoring on primary checkout
  - branch: plan/windowing
    worktree_path: /Users/me/Code/harmonius-worktrees/PLAN-platform-windowing
    phase: plan
    subsystem: platform
    plan_id: PLAN-platform-windowing
    claimed_at: 2026-04-13T14:00:00Z
    owner: user
    reason: Manual fix in plan worktree before handing back to harmonize
```

## Stale locks

Locks with **`claimed_at`** older than 24 hours and no matching activity in phase or plan progress
are **stale**. Harmonize reports them; it does not auto-clear.
