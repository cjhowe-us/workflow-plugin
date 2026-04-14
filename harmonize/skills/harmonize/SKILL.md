---
name: harmonize
description: >
  Full SDLC orchestration for Harmonius. Entry point for every stage of the software
  development lifecycle: feature/requirement/user-story ideation, hierarchical design, design
  review, implementation planning, hierarchical TDD execution, PR review, and release.
  Routes user intent to phase-specific sub-skills for interactive work while a background
  supervisor runs the orchestration tree asynchronously and opens many small draft PRs for
  human review. Use whenever the user wants to plan, design, implement, review, release, or
  check status of anything in Harmonius, or whenever "harmonize" is mentioned.
---

# Harmonize

Master entry point for the Harmonius software development lifecycle. Coordinates all four SDLC
phases across hundreds of subsystems. The user never edits files directly — sub-skills ask questions
and spawn background agents to do every file write, git operation, and PR action. Progress is
tracked via state files, hierarchical task lists, and many small GitHub PRs so human review stays
readable.

## Two channels

| Channel | What runs | User sees |
|---------|-----------|-----------|
| Foreground (this conversation) | `harmonize` + sub-skills + AskUserQuestion | Interactive decisions |
| Background (`Agent(run_in_background: true)`) | master agent, phase orchestrators, workers | Progress notifications, PRs |

The main conversation stays responsive because every heavy agent runs as a background task. State
persists to files, so the user can step away and come back. When a background task completes, the
foreground session receives a completion notification.

## The user never edits directly

Interactive sub-skills use `AskUserQuestion` to collect user input. Sub-skills then either:

1. Spawn a background agent to do the writing (preferred for any non-trivial file change), or
2. Write files themselves — but only when the change is tiny and the user has approved

The user ONLY provides feedback and decisions. All file writes, git operations, and GitHub PR
actions flow through agents. This keeps every change traceable to a specific agent task, a specific
PR, and a specific review cycle.

## Lifecycle phases

| # | Phase | Orchestrator agent | Workers |
|---|-------|--------------------|---------|
| 1 | Specify | `specify-orchestrator` | `feature-author`, `requirement-author`, `user-story-author` |
| 2 | Design | `design-orchestrator` | `subsystem-designer`, `interface-designer`, `component-designer`, `integration-designer`, `design-reviewer`, `design-reviser` |
| 3 | Plan + TDD + review | `plan-orchestrator` | `plan-author`, `plan-implementer`, `pr-reviewer` |
| 4 | Release | `release-orchestrator` | `release-notes-author`, `changelog-updater`, `tagger` |

Phase 3 is a nested pipeline (plan → TDD → review → merge → dependents) driven by the existing
`plan-orchestrator`.

## Sub-skills per phase

Each phase has an interactive sub-skill. The user loads one when they want to think through a
specific resource; the sub-skill claims a coarse lock so background workers stay away.

| Sub-skill | For | Coarse lock type |
|-----------|-----|------------------|
| `harmonize-specify` | Features, requirements, user stories | `specify` |
| `harmonize-design` | Subsystem, interface, component, integration designs | `design` |
| `harmonize-plan` | Implementation plans | `plan` |
| `harmonize-implement` | Active plan TDD execution | `plan` |
| `harmonize-review` | Draft PR review | `review` |
| `harmonize-release` | Release process | `release` |

## Coarse locks

A lock is a `(phase, subsystem)` pair. One lock covers ALL files in a subsystem for a given phase.
Different phases of the same subsystem can proceed in parallel; different subsystems in the same
phase can proceed in parallel.

### Lock file (`docs/plans/locks.md`)

```yaml
locks:
  - phase: design
    subsystem: core-runtime
    claimed_at: 2026-04-13T15:00:00Z
    owner: harmonize-design
    reason: User revising ECS archetype API
```

### Subsystems

Subsystem identifiers match the `docs/design/<subsystem>/` directory names: `ai`, `animation`,
`audio`, `content-pipeline`, `core-runtime`, `data-systems`, `game-framework`, `geometry`, `input`,
`integration`, `networking`, `physics`, `platform`, `rendering`, `simulation`, `tools`, `ui`, `vfx`.

### Stale locks

A lock older than 24 hours with no matching phase-progress activity is considered stale. The
harmonize master agent reports stale locks but never auto-clears them — the user must decide.

## Hierarchical task lists

All tasks live in the single shared `TaskCreate` list, but every task is tagged with an `owner` so
the list can be filtered by level.

| Owner | Source |
|-------|--------|
| `main` | User-facing session tasks (interactive sub-skills) |
| `harmonize` | Master orchestrator steps |
| `specify-orchestrator` | Phase 1 coordination |
| `design-orchestrator` | Phase 2 coordination |
| `plan-orchestrator` | Phase 3 coordination |
| `release-orchestrator` | Phase 4 coordination |
| `feature-author`, `subsystem-designer`, `plan-implementer`, ... | Fine-grained worker steps |

Filter with `TaskList` then inspect the `owner` field. Each worker creates a parent task for its
invocation and intermediary tasks for each step (read inputs, check lock, open PR, draft file, run
lint, push, update progress).

## Per-phase progress files

| File | Tracks |
|------|--------|
| `docs/plans/progress/phase-specify.md` | Per-subsystem F/R/US counts + PRs |
| `docs/plans/progress/phase-design.md` | Per-subsystem design doc + review status + PRs |
| `docs/plans/progress/phase-plan.md` | Per-subsystem plan-authoring + execution rollup + PRs |
| `docs/plans/progress/phase-release.md` | Release history + current release PR |
| `docs/plans/progress/PLAN-<id>.md` | Existing per-plan detail (Phase 3 workers) |

Phase orchestrators update their phase-progress file at the start and end of every pass.

## Many small PRs per phase

Every worker agent opens at least one draft GitHub PR at the start of its work. This makes every
change reviewable on GitHub in small chunks, independent of whether the user is interacting
foreground or the orchestrator is running background.

| Phase | Worker | PR title convention |
|-------|--------|---------------------|
| Specify | feature/requirement/user-story-author | `[specify] <subsystem>:<topic>` |
| Design | subsystem-designer, etc. | `[design] <subsystem>:<topic>` |
| Plan | plan-author | `[plan] <subsystem>:<topic>` |
| TDD | plan-implementer | `[impl] PLAN-<id>` |
| Release | release-notes-author, changelog-updater | `[release] <version>` |

A worker may open multiple PRs if its work decomposes into independent chunks. The pr-reviewer does
not open PRs; it commits review fixes to an existing PR.

## State files

| File | Purpose | Writer |
|------|---------|--------|
| `docs/plans/index.md` | Root plan — total topological order | plan-author, plan-orchestrator |
| `docs/plans/<subsystem>/<topic>.md` | Individual plan files | plan-author |
| `docs/plans/progress/phase-{specify,design,plan,release}.md` | Phase rollups | Phase orchestrators |
| `docs/plans/progress/PLAN-<id>.md` | Per-plan detail | plan-implementer, pr-reviewer |
| `docs/plans/locks.md` | Active coarse locks | Sub-skills (claim/release), harmonize agent (report only) |
| `docs/plans/in-flight.md` | Running background tasks | harmonize agent, phase orchestrators |

## Routing on invocation

When the user invokes this skill, parse the argument and route:

| Argument | Response |
|----------|----------|
| (none) | Print SDLC status, run manual merge-detection backup, ask what to work on |
| `status` | Print SDLC status summary, do not dispatch |
| `run` | Dispatch the `harmonize` master agent in background for a full SDLC pass |
| `stop` | Stop all in-flight tasks, report, do not release locks |
| `cron` | Bootstrap the merge-detection cron |
| `merge-detect` | Dispatch `harmonize` master in `merge-detection` mode (manual merged-PR check) |
| `merge-detection` | Same as `merge-detect` |
| `resume <phase> <subsystem>` | After a sub-skill releases a lock, re-dispatch for that resource |
| `specify [topic]` | `Skill(harmonize-specify, <topic>)` |
| `design [doc-path]` | `Skill(harmonize-design, <doc-path>)` |
| `plan [plan-id]` | `Skill(harmonize-plan, <plan-id>)` |
| `implement [plan-id]` | `Skill(harmonize-implement, <plan-id>)` |
| `review [pr-url]` | `Skill(harmonize-review, <pr-url>)` |
| `release [version]` | `Skill(harmonize-release, <version>)` |

Always announce "Loading harmonize-X..." before calling a sub-skill so the user sees the context
switch.

## Cron bootstrap

Every invocation of this skill:

1. Call `CronList`
2. Look for a job whose prompt contains `[harmonize-merge-detect]`
3. If missing or near 7-day expiry, call `CronCreate` with:

| Parameter | Value |
|-----------|-------|
| `cron` | `7,22,37,52 * * * *` |
| `recurring` | `true` |
| `durable` | `true` |
| `prompt` | `[harmonize-merge-detect] /harmonize run` |

The cron fires every 15 minutes on off-minutes; Claude receives the prompt, the CLAUDE.md rule maps
`/harmonize` to this skill, and the skill routes to `run` mode which dispatches the harmonize master
agent in background.

4. If `CronList` or `CronCreate` is unavailable, errors, or returns no durable job after a best
   effort, continue — do not block the session on cron alone.
5. In that case (and whenever the user invokes `/harmonize` with no extra argument), run the
   **manual merge-detection backup** below so merged PRs still advance the plan graph without
   waiting for the next cron tick.

## Manual merge-detection backup

Purpose: detect merged Phase 3 PRs (`gh`), advance `PLAN-*` progress, unblock dependents — same
subset as the `merge-detection` mode on the `harmonize` master agent.

### When to run

- User says `/harmonize merge-detect` or `/harmonize merge-detection`
- User says `/harmonize` with no argument (after printing status)
- Cron bootstrap in the previous section did not confirm an active `[harmonize-merge-detect]` job

#### How to run

1. Prefer background dispatch:

   ```text
   Agent({
     subagent_type: "harmonize",
     run_in_background: true,
     prompt: "mode: merge-detection [harmonize-merge-detect-manual] — PR merge → PLAN advance"
   })
   ```

2. If background agents are not available, instruct the session to perform the same steps as the
   `harmonize` master agent’s merge-detection pass (read state, delegate merge check to
   `plan-orchestrator` per agent playbook).

This pass is idempotent: repeating it should not advance status twice for the same merge.

## Completion notifications

When this skill (or any sub-skill) dispatches a background agent via
`Agent(run_in_background: true)`, the foreground conversation receives a completion notification
with the task output file path when the task finishes. Use this to resume interactive work without
polling.

The long chain (harmonize master → phase orchestrator → workers) does not rely on notifications
because each link is short-lived; state files are the authoritative channel. Notifications are used
only at the top level where an interactive session is waiting for a specific dispatched chunk.

## SDLC status format

```text
harmonize status — 2026-04-13T16:00:00Z

Phase 1 Specify:     159 / 281 features, 161 / 281 reqs, 161 / 281 stories (3 PRs open)
Phase 2 Design:      281 authored, 12 in review, 0 revising (5 PRs open)
Phase 3 Plan + TDD:  42 total, 7 merged, 2 submitted, 3 code_complete, 5 started
                     25 not_started, 18 blocked by deps
Phase 4 Release:     last 0.1.0 on 2026-03-15, no release in progress

Interactive locks (2):
  - design:core-runtime — User revising ECS archetype API (30m ago)
  - plan:core-runtime — User stepping through ECS archetype plan (1h ago)

In-flight background tasks: 8
  - feature-author (ai, task abc123, started 14:30Z)
  - plan-implementer (PLAN-platform-windowing, task def456, started 14:45Z)
  ...

Cron: active, next fire in 7 minutes
```

## Replaces

| Legacy | Replaced by |
|--------|-------------|
| `workflow` skill | this skill |
| `workflow-supervisor` agent | `harmonize` master agent |
| `ideate` skill | `specify-orchestrator` + `harmonize-specify` + workers |
| `coding-supervisor` agent | `plan-implementer` (already existed) |
| `release-supervisor` agent | `release-orchestrator` |
| `document-author` agent | Phase-specific authors (feature-author, subsystem-designer, plan-author, ...) |

## When to use this skill

- At the start of any Harmonius work session — to check status
- When the user mentions "harmonize" in any form
- When the merge-detection cron fires
- When the user wants to author, revise, implement, review, or release anything

## When NOT to use this skill

- Isolated code edits unrelated to SDLC flow
- Questions about specific code behavior — use Read/Grep directly
- Git operations outside harmonize plan execution
