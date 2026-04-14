---
phase: specify
started_at: null
last_updated: null
---

# {Phase Name} Progress

Per-subsystem rollup of {phase name} work across the Harmonius project. Updated by the
phase orchestrator on every pass; read by the harmonize master agent to compute the next
ready set.

Use one instance of this template per phase:

- `docs/plans/progress/phase-specify.md`
- `docs/plans/progress/phase-design.md`
- `docs/plans/progress/phase-plan.md`
- `docs/plans/progress/phase-release.md`

## Subsystems

| Subsystem | Status | Artifacts | Plans | Open PRs | Last update |
|-----------|--------|-----------|-------|----------|-------------|
| {name} | {not_started / in_progress / review / done} | {counts} | {links or —} | {#num, #num} | {timestamp} |

**Plans column:** markdown link(s) to `docs/plans/<subsystem>/<topic>.md` for this subsystem. Use
**`—`** in `phase-specify.md`, `phase-design.md`, and `phase-release.md`. In **`phase-plan.md`**,
every subsystem with implementation work **must** list each plan file
(e.g. `[ecs.md](../core-runtime/ecs.md)`). Optionally add the matching per-plan progress file in
the same cell (e.g. · [`PLAN-…`](PLAN-core-runtime-ecs.md)).

Status values:

| Status | Meaning |
|--------|---------|
| `not_started` | No work begun for this subsystem in this phase |
| `in_progress` | One or more workers dispatched; artifacts being created |
| `review` | Artifacts authored, awaiting review on GitHub PR |
| `done` | All PRs merged for this subsystem in this phase |

## PR roster

All PRs opened during this phase, grouped by subsystem. Each PR links to GitHub; each entry
names the worker agent that authored it so review findings can be routed back.

| PR | Subsystem | Title | Worker | Opened | State |
|----|-----------|-------|--------|--------|-------|
| #{num} | {subsystem} | {title} | {agent} | {date} | {draft / open / merged / closed} |

## Event log

Append one line per significant event using ISO 8601 UTC timestamps.

- {timestamp} — {event}
