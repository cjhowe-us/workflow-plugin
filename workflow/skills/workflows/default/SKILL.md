---
name: default
description: |-
  Default orchestrator + tutor. Entry point for `/workflow` — interprets the user's free-form request, loads only the files needed, dispatches workers, polls providers, renders the dashboard. On first invocation (when `tutor.completed` is not set in preferences), walks the user through the two primitives (workflow, artifact), installed extensions, and a guided try-it. Subsequent invocations go straight to dashboard + intent routing.
---

# default

The orchestrator workflow. Every `/workflow` invocation loads `default` (or a workspace/user
override) and hands it the user's free-form input. The orchestrator does the rest.

## First-run tutor

On the first invocation (when `preferences:user.tutor.completed` is falsy), the `interpret` step
recognizes any input and routes to a tutorial sequence instead of normal interpretation:

1. Welcome + the two primitives.
2. Enumerate installed extensions and what they contribute.
3. Offer a guided try-it — pick a simple workflow (e.g. `cut-release`), walk through inputs,
   dispatch, watch progress.
4. Set `preferences:user.tutor.completed = true` via the `preferences` provider.

The user can always re-open the tutor with `/workflow teach me again`.

## Normal-run routing

Against the registry, decide what the user wants:

- Dashboard — empty input, "status", "what am I running" → load `tracking` skill, query all active
  execution providers, render.
- Start a workflow — "start bug-fix on #42", "run cut-release" → resolve workflow name against
  registry, collect inputs via `AskUserQuestion`, dispatch a worker.
- Inspect / resume — "show me the sdlc run on X", "resume exec-A" → load the specific execution's
  provider, render details, offer next actions.
- Tunnel — `tunnel <worker-id>` → open a tunnel via `tunneling` skill.
- Author / update / review / delete — "create a new workflow called X", "update the bug-fix
  workflow", "review the cut-release workflow", "delete my-template" → delegate to the
  `conductor` workflow with the matching `mode` input. `conductor` is the only meta-workflow:
  a workflow that operates on other workflows + artifact templates. No separate review/update
  flows.

When intent is ambiguous, emit a single-line clarification question (`AskUserQuestion`) rather than
guessing.

## Load order

Always load first (already in memory via the registry):

- `workflow-contract` skill (when working with workflow files).
- `artifact-contract` skill (when invoking providers).
- `tracking` skill (for every dashboard render).

Load on demand:

- Target workflow SKILL.md (only when the user chose one).
- Target artifact-template SKILL.md (only when generating an artifact).
- Specific provider SKILL.md (only when reading/writing its scheme).

## Invariants

- The orchestrator never writes artifacts directly — it delegates to workers via teammate dispatch,
  or to `conductor` for authoring.
- The orchestrator never caches provider state across turns — every dashboard render is a fresh
  query.
- The orchestrator is plugin-immutable. Any change lands via an external PR or an override-scope
  copy named `default` that shadows this one.
