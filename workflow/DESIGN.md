# workflow plugin — design document

Source of truth for the workflow primitive's architecture. Append-only changelog at the bottom records material design
decisions. Edits that change these choices must add a dated entry here.

Artifact primitives (artifacts, artifact templates, artifact providers) live in the separate
[`artifact`](../artifact/DESIGN.md) plugin. This plugin depends on it.

## Problem

Claude Code teams need orchestrated, multi-workflow automation that spans product, project, and SDLC work; coordinates
multiple developers without a central server; reports progress through systems teams already use (PRs, issues, docs);
and keeps the plugin surface minimal enough that authors compose domain workflows without a new DSL.

## Non-goals

- A task tracker replacing Jira / Linear.
- Preserving v1 coordinator data — v2 is a fresh install.
- Re-implementing artifact or template mechanics. Those are owned by the artifact plugin.

## Goals

- **A rich workflow DSL is the whole point.** Sequential + parallel composition, dynamic branches decided by an LLM
  judge, human gates, retries, retroactive steps, sub-workflow composition, typed inputs/outputs, rule declarations for
  PreToolUse enforcement, step signatures for ledger diff. The DSL should be expressive enough that every domain models
  cleanly. When an author wants a new shape, the answer should always be "express it as composition within the DSL,"
  never "add a new primitive to the engine."
- **Dogfood the artifact plugin.** Every runtime concern — execution lifecycle, progress logs, step artifacts, worker
  handoff state — is an artifact managed by an artifact provider. The workflow plugin is itself a reference plugin for
  the artifact plugin.

## Foundational concepts

**One composition primitive: the workflow.** Supporting objects: worker, orchestrator (role not primitive), execution
(an artifact managed by the `execution` provider this plugin ships).

- **Workflow** — a markdown file with YAML frontmatter (Claude Code skill shape) declaring a runnable DAG of steps with
  typed inputs and outputs. Steps may reference other workflows as sub-workflows (*composition*). Workflows live in
  plugin / user / workspace / override scope and are discovered by the artifact plugin's `scripts/discover.sh`.

- **Worker** — a teammate agent that executes workflows. One role: `worker`. Workers are reusable and switch between
  worktrees as they move between executions. At any moment a worktree has at most one active worker; across time a
  worker may visit many. Concurrent executions can run multiple workers in parallel on disjoint worktrees.

- **Orchestrator (role, not primitive)** — any worker running the configured orchestrator workflow (default: `default`)
  plays the orchestrator role for that run. When `/workflow` is invoked, a worker is pointed at that workflow; it
  interprets intent, loads only what is needed, dispatches other workers, polls providers, renders the dashboard.

- **Execution** — the artifact produced when a workflow runs. Backed by the `execution` provider shipped here, which
  defaults to a GitHub PR (description + comments). Progress, step ledger, lifecycle status, owner, and dependencies all
  live inside the execution artifact via the provider contract.

## Key invariants

1. **One composition primitive: the workflow.** Executions, documents, PRs, issues, etc. are artifacts from the
   perspective of the workflow — handled through the artifact plugin's providers.
2. **At any moment, one worker per worktree.** Workers may switch between worktrees over time, but two workers are never
   in the same worktree concurrently.
3. **One worktree per execution. Parent and children run in parallel on disjoint worktrees.** Children never acquire any
   lock on parent and cannot write to parent's artifacts unless the parent explicitly grants write access.
4. **Child PR `base = <parent PR head branch>`.** Merges bubble up.
5. **Parent detects child completion by polling the child execution's provider `status`.** Progress renders on demand by
   querying provider `progress`. No caches.
6. **Multi-developer presence uses a per-GitHub-user private gist** (`workflow-user-lock-<gh-user-id>`) that tracks
   active sessions across machines. Artifact-level locks (PR assignee, etc.) enforce single-writer per artifact.
7. **One orchestrator per machine** (flock at `$XDG_STATE_HOME/workflow/orchestrator.lock`).
8. **Plugin files are immutable to agents.** Changes come via override scope or external PR.
9. **Only `aborted` is terminal.** Failures become `needs_attention`, resolvable by the user without losing progress.
10. **`SendMessage` content is strict JSON, unwrapped and unfenced.** One JSON object per message. Receivers parse
    strictly; malformed input fails fast.
11. **Durable workflow state lives on GitHub.** Every piece of state that must survive a session, move between machines,
    or be seen by other developers is stored on GitHub via an artifact provider (execution on gh-pr by default).
12. **Bidirectional sync + retroactive completion.** Workflow definitions are living; execution artifacts are
    authoritative for what happened. On every scan the engine diffs each execution's step ledger against its workflow's
    current definition; gaps are surfaced as *retroactive steps* the user may backfill. External mutations to artifacts
    (PR edited on github.com) are reconciled on the next scan. No missed migrations.

## Dogfooding

- `workflow` plugin consumes the `artifact` plugin for every provider call. The worker dispatches through
  `artifact/scripts/run-provider.sh`; artifact templates are instantiated via
  `artifact/scripts/instantiate-template.sh`.
- This plugin ships the `execution` artifact provider (the workflow-domain one) plus three workflow-shape artifact
  templates (write-review, plan-do, workflow-execution). Their `manifest.json` + `instantiate.sh` files are read by the
  artifact plugin's template subsystem — the workflow plugin is itself a reference plugin for the artifact plugin.
- Domain plugins (`workflow-sdlc`) consume this plugin in turn: they ship workflows and artifact templates that compose
  ours.

## Design changelog

Append-only.

| Date       | Decision |
|------------|----------|
| 2026-04-17 | Initial coordinator → workflow rename + four plugins. |
| 2026-04-17 | One agent role (`worker`); composition-only reuse; PR per execution; hierarchical branch / worktree / execution names. |
| 2026-04-17 | Assignee-only lock; global orchestrator flock; LLM judge carries confidence. |
| 2026-04-17 | Parent and children run in parallel; children never lock parent. |
| 2026-04-17 | Plugin files immutable; changes via override scope or external PR. |
| 2026-04-18 | Workers are reusable and switch between worktrees; worktree-level exclusivity preserved at any moment. |
| 2026-04-18 | Multi-developer presence is a per-GitHub-user private gist; multi-machine allowed. |
| 2026-04-18 | Identity comes from `gh auth status`; no login dialog. |
| 2026-04-18 | Orchestrator is a role, not a primitive. |
| 2026-04-18 | `SendMessage` protocol is strict, unwrapped, unfenced JSON. |
| 2026-04-18 | Bidirectional sync between workflows and artifacts. Step ledger per execution with step signatures enables retroactive-step detection. No missed migrations. |
| 2026-04-18 | **Split `workflow` into two reference plugins:** artifact-side (providers, templates, entry skill) moves to the new `artifact` plugin; this plugin keeps worker, orchestration, execution provider, workflow-shape templates, `/workflow` entry, meta-workflows. Workflow depends on artifact. |
| 2026-04-18 | Workflow-shape artifact templates (write-review, plan-do, workflow-execution) ship here because their instantiation dispatches a workflow execution — a workflow-domain concern — via the `execution` provider. |
| 2026-04-18 | **Layout fix + python consolidation.** Workflows move out of `skills/workflows/<n>/SKILL.md` into top-level `workflows/<n>/workflow.md`; they're not Claude Code skills, they're workflow artifacts with their own runtime. All bash hooks/scripts/backend/tests replaced with python; `hooks.json` now invokes `python3 .../<hook>.py` directly (zero `.sh` files remain). Execution provider/backend move to the new scheme/storage architecture: `artifact-schemes/execution/` (vertex, pydantic-typed per-subcommand I/O) + `artifact-storage/execution-gh-pr/`. Workflow plugin gains its own `pyproject.toml` + `scripts/workflowlib/` library, imports `artifactlib` for shared concerns. `hooks/pretooluse-no-self-edit` regression fix: the old bash hook blocked every write when `CLAUDE_PLUGIN_DIRS` was unset (empty-array expansion → `/*` case match); the python port collapses cleanly. Plugin bumps to `2.0.0.dev0`; requires `artifact >= 2.0.0.dev0`. |
