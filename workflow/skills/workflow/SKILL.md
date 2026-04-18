---
name: workflow
description: This skill should be used when the user types `/workflow` or asks to "run a workflow", "start a workflow", "show my dashboard", "what am I running", "resume an execution", "retry a step", "abort", "release", "tunnel to a worker", "raise my wip limit", or mentions workflow executions in general. Dispatches the configured orchestrator (default `default`) and exposes sub-commands for run/status/resume/retry/skip/abort/release/tunnel/untunnel/limit.
---

# workflow

The `/workflow` entry point. Dispatches the configured orchestrator (the workflow named in
`preferences:user.orchestrator` or `preferences:workspace.orchestrator`; default `default`) and hands it the user's
free-form input.

Artifact operations (authoring templates, inspecting artifacts by URI, listing providers) go through the separate
`/artifact` skill in the [`artifact`](../../../artifact) plugin. This skill stays focused on workflow runtime.

## Sub-command shape

Map the user's input to one of these patterns before loading details. For anything ambiguous, prompt once via
`AskUserQuestion`.

| Pattern                                      | What to do                                             | Load reference |
|----------------------------------------------|--------------------------------------------------------|----------------|
| empty / "status" / "what am I running"       | Render dashboard (queries artifact providers live)     | `references/tracking.md` |
| "run/start <workflow> [...]"                 | Instantiate via `workflow-execution` template          | `references/running.md` |
| "resume <change>"                             | Re-enter at current step of the named execution        | `references/running.md` |
| "retry <change> <step>"                       | Reset retry count + resume                             | `references/running.md` |
| "skip <change> <step>"                        | Mark step complete-skipped                             | `references/running.md` |
| "abort <change>"                              | Terminal abort via the execution provider              | `references/running.md` |
| "release <change>"                            | Clear assignee lock (manual transfer)                  | `references/multi-dev.md` |
| "tunnel <worker>" / "untunnel"                | Open / close direct user↔worker channel                | `references/tunneling.md` |
| "limit <N>" / "raise my wip cap"              | Adjust wip caps in `preferences:user`                  | `references/running.md` |
| "create <workflow>" / "new template"          | Dispatch `conductor` (mode=create)                     | `references/running.md` |
| "update <uri>" / "edit my workflow"           | Dispatch `conductor` (mode=update)                     | `references/running.md` |
| "review <uri>"                                | Dispatch `conductor` (mode=review)                     | `references/running.md` |
| "delete <uri>"                                | Dispatch `conductor` (mode=delete)                     | `references/running.md` |

## Dispatch primer

Every "start" / "run" path instantiates the `workflow-execution` artifact template shipped by this plugin. That
template's `instantiate.sh` calls the `execution` provider's `create`, which opens a GitHub PR (by default), seeds the
wf:summary + wf:ledger sections, and returns the execution URI. A worker teammate is then dispatched at the new
worktree.

The artifact plugin's `run-provider.sh` is the uniform dispatch surface for every provider call a worker makes during
execution.

## Author your own

Custom workflows drop into one of four scope directories (override > workspace > user >
plugin). The plugin-shipped ones are immutable; all authoring goes through `conductor`:

| Goal                             | Command                                            |
|----------------------------------|----------------------------------------------------|
| Project-wide (committed to repo) | `/workflow create <name> --scope workspace`        |
| Personal (across all projects)   | `/workflow create <name> --scope user`             |
| One-off (this working tree)      | `/workflow create <name> --scope override`         |

Same pattern for `update`, `review`, `delete`. All four dispatch the `conductor` workflow
with the matching `mode` input. See `references/workflow-contract.md` §Scopes for path
details and the decision table.

## First run (tutor)

On the first invocation after install, `preferences:user.tutor.completed` is falsy. Route to the tutor flow: welcome,
the workflow + artifact primitives (reference the artifact plugin's docs), installed extensions, and a guided try-it.
Set `tutor.completed = true` on finish.

Re-open later with "teach me again" or equivalent.

## Invariants held here

- No in-repo runtime state.
- Identity from `gh auth status`; no login dialog.
- One orchestrator per machine (flock).
- Progress rendered on demand from provider queries; no caches.
- Plugin files are immutable; writes go through override / workspace / user scope via the
  `conductor` workflow (create / update / review / delete modes, all on top of the artifact
  plugin's CRUD surface).

## References (load on demand)

- `references/running.md` — dispatch, WIP caps, retries, blockers, needs-attention, aborts.
- `references/tracking.md` — dashboard format, provider query cadence.
- `references/tunneling.md` — tunnel semantics, envelope shapes, force-close behavior.
- `references/multi-dev.md` — identity, presence gist, assignee lock, ownership transfer.
- `references/workflow-contract.md` — workflow file schema (needed when inspecting an execution's workflow or explaining
  its shape).
