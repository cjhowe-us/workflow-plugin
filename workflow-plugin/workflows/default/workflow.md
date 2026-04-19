---
name: default
description: |-
  Default orchestrator + first-run seed + tutor. Entry point for `/workflow`. A four-step DAG: `seed` (skipped when the workspace and user are already initialized) → `tutor` (skipped when the user has completed it) → `interpret` (intent routing against the registry) → `act` (dispatch or render).
---

# default

The orchestrator workflow. Every `/workflow` invocation loads `default` (or a workspace / user override) and hands it
the user's free-form input plus two flags derived from preferences:

- `initialized` — true when both `preferences:user.extra.workflow_initialized` and
  `preferences:workspace/<repo-hash>.extra.workflow_initialized` are true.
- `tutor_completed` — true when `preferences:user.extra.tutor_completed` is true.

The `/workflow` skill computes these flags and injects them as workflow inputs before dispatch. A conditional step
(`when:` in the manifest) fires only when its flag is falsy; skipped steps flow through to the next transition target
per the `workflow-contract` reference.

## Step: seed (when: `initialized == false`)

On the very first invocation for a (user, workspace) pair, detect the environment and walk the user through three
independent backend confirmations. Every backend is pluggable and optional — the values written below are
*defaults the seed proposes*, not decisions the plugin makes on the user's behalf.

1. Call `workflowlib.seed.detect_repo()` — returns `RepoFacts(is_git, on_github, remote_url, repo_slug, root)`.
2. If `on_github` and any of the three backends will default to a GitHub backend, call `workflowlib.auth.require()`
   first (raises a user-visible blocker with `gh auth login` hint if not authenticated).
3. For each of the three backend slots, emit one `AskUserQuestion`:
   - **Execution state storage** — proposed default `execution-gh-pr` on GitHub, none off GitHub. Options: accept the
     default, pick another available backend, or decline (leave unset — the user can wire one up later via the
     `conductor` workflow).
   - **Lock / presence storage** — proposed default `gh-gist` on GitHub, none off GitHub. Options: accept, pick another
     backend, or decline.
   - **Dependency overlay** — proposed default `gh-issue` on GitHub, none off GitHub. Options: accept (issues cite
     implementation PRs to form a graph overlay), pick another backend, or decline.
4. Pass the three answers to `workflowlib.seed.seed(choices={...})`. Empty string in the mapping means declined; a
   backend name means accepted / chosen.
5. The seed writes only the backends the user accepted:
   - `preferences:user.extra.workflow_initialized = true`
   - `preferences:user.extra.storage_lock = <chosen>` (omitted when declined)
   - `preferences:workspace/<repo-hash>.extra.workflow_initialized = true`
   - `preferences:workspace/<repo-hash>.extra.storage_state = <chosen>` (omitted when declined)
   - `preferences:workspace/<repo-hash>.extra.overlay_dependencies = <chosen>` (omitted when declined)
6. Emit a progress entry summarizing what was wired up, and fall through to `tutor`.

## Step: tutor (when: `initialized == false || tutor_completed == false`)

Walks the user through the two primitives (workflow, artifact), enumerates installed extensions, and offers a guided
try-it. Fires whenever `seed` ran (`initialized` was false at dispatch time) **or** `tutor_completed` is false — the
first-run path always chains seed → tutor, even if `tutor_completed` is somehow true. Sets
`preferences:user.extra.tutor_completed = true` on finish. The user can re-open later with `/workflow teach me again`.

## Step: interpret

Against the registry, decide what the user wants:

- Dashboard — empty input, "status", "what am I running" → load `tracking` skill, query all active execution providers,
  render.
- Start a workflow — "start bug-fix on #42", "run cut-release" → resolve workflow name against the registry, collect
  inputs via `AskUserQuestion`, dispatch a worker.
- Inspect / resume — "show me the sdlc run on X", "resume exec-A" → load the specific execution's provider, render
  details, offer next actions.
- Tunnel — `tunnel <worker-id>` → open a tunnel via `tunneling` skill.
- Author / update / review / delete — "create a new workflow called X", "update the bug-fix workflow", "review the
  cut-release workflow", "delete my-template" → delegate to the `conductor` workflow with the matching `mode` input.
  `conductor` is the only meta-workflow.

When intent is ambiguous, emit a single-line clarification question (`AskUserQuestion`) rather than guessing.

## Step: act

Execute the routing decision produced by `interpret`. Dispatches a teammate, renders a dashboard, or fires a provider
call — whichever the interpretation selected.

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

- The orchestrator never writes artifacts directly outside the `seed` step — it delegates to workers via teammate
  dispatch, or to `conductor` for authoring.
- The orchestrator never caches provider state across turns — every dashboard render is a fresh query.
- The orchestrator is plugin-immutable. Any change lands via an external PR or an override-scope copy named `default`
  that shadows this one.
