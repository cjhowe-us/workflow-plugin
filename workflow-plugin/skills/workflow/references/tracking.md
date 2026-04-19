# tracking

The dashboard is rendered on demand by the `default` orchestrator. Data comes exclusively from artifact providers — no
local cache, no per-session materialized view.

## Inputs

1. **Registry** — the shallow registry at `$XDG_STATE_HOME/workflow/ registry.json` supplies names + scopes, not state.
2. **Provider queries** — `execution.list --filter '{"status":"running"}'` (and related filters) returns active
   executions. For each, follow up with `execution.status`, `execution.progress`, and the retroactive-diff pass.
3. **Session state** — orchestrator flock + in-session dispatch ledger at `$XDG_STATE_HOME/workflow/dispatch.json` for
   worktree ownership and worker assignments.

## Render shape (compact)

```text
[workflow] session=sess-01HXX user=alice · 3 active · 1 needs attention

installed  workflows=8 · templates=16 · schemes=70 · storages=12

running
  ▸ bug-fix/exec-A  · step=fix     · since 12m · @alice
  ▸ cut-release/Z   · step=tag     · since 2m  · @alice
needs_attention
  ✗ sdlc/exec-Q     · step=verify  · retries=3 · since 2h

retroactive
  • db-migration/exec-A — 1 new step since 2026-04-01 run
```

The `installed` line is a registry-only summary — counts come from `$XDG_STATE_HOME/workflow/registry.json` (workflows,
templates, schemes, storages). No provider calls; cost is a single file read. Per-artifact listings remain a separate
detail view.

Detail views expand one execution at a time:

```text
execution: bug-fix/exec-A
  pr: owner/repo#142
  started: 2026-04-18T09:12:00Z · owner: alice
  steps:
    ✓ triage     — complete (9 progress events)
    ▸ fix        — running (3 min, 12 progress events)
    · release-note — pending
  blockers: (none)
  retroactive: (none)
```

## Query loop

For every active execution the orchestrator:

1. Calls `execution.status --uri U`.
2. Calls `execution.progress --uri U` (may paginate; first N entries only in dashboard mode).
3. Runs the retroactive-diff: fetch the current workflow definition, compare its step set against the execution's step
   ledger, flag any missing or signature-drifted steps.

Results render fresh each render. No caches means latency scales with the number of executions × provider round-trip;
for up to ~10 executions this is sub-second. Beyond that, the orchestrator trims the rendered set
(`top 10 by last activity`) unless the user asks for more.

## Polling cadence

Polling is per-provider (`min_poll_interval_s` in provider frontmatter, default 30). The dashboard does not poll — it
reads on-demand. Background reconciliation is driven by the `teammateidle-rescan.sh` hook and the periodic heartbeat
task, not by the dashboard.

## Natural-language queries

"What am I running?" / "any blockers on the sdlc work?" / "show me the bug-fix from yesterday" all route through the
default orchestrator, which narrows the provider query set before rendering. The tracking skill supplies the rendering
helpers; orchestrator supplies the intent.
