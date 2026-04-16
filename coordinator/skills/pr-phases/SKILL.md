---
name: pr-phases
description: >
  The PR-phase model used by the coordinator plugin. Every phase of
  software work — specify, design, plan, implement, release, docs — is
  tracked as a GitHub pull request. Draft PR = started; ready-for-review
  PR = phase complete; merged PR = phase artifact landed. No GitHub
  issues, no projects. Read this to understand what each phase PR should
  contain and how phases chain via the PR body-marker's `blocked_by`
  field. Covers work, personal, group, and OSS contexts.
---

# PR phases — the unit-of-work model

All work in the coordinator model flows through pull requests. There are no issues, tasks, cards,
projects, or ticket numbers. The PR itself is the task. Its title is the task description. Its body
carries the artifact (spec, design, plan, code, release notes, or docs). Its draft / ready / merged
state is the phase's lifecycle. A single HTML-comment marker at the bottom of the body carries
coordinator state (lock + `blocked_by`).

## The six phases

| Phase       | Artifact the PR contains                                                 | Done signal                         |
|-------------|--------------------------------------------------------------------------|-------------------------------------|
| `specify`   | A spec document committed to `specs/<topic>.md` (or similar convention)  | PR marked ready-for-review          |
| `design`    | A design document (architecture, diagrams, API sketch) as markdown       | PR marked ready-for-review          |
| `plan`      | A breakdown of implementation PRs with the `blocked_by` chain planned     | PR marked ready-for-review          |
| `implement` | Code changes for one planned sub-scope                                   | PR marked ready-for-review          |
| `release`   | Version bump, changelog entry, release notes                             | PR merged (human approval gate)     |
| `docs`      | User-facing documentation update (README, site, migration notes)         | PR marked ready-for-review          |

Phase is encoded on each PR as the label `phase:<name>`. The presence of any `phase:*` label is also
the in-scope signal for the orchestrator's scan — that's the opt-in.

## Lifecycle per PR

1. **Open as draft.** Orchestrator or a human opens the PR via
   `scripts/ensure-pr.sh --phase <phase> --title "..."`. Initial commit is a stub; the worker fills
   it in.
2. **Worker picks up.** Coordinator dispatches a worker teammate which splices the coordinator
   marker into the PR body (holding the lock) and begins committing on the PR's branch.
3. **Heartbeat while working.** Worker re-stamps `lock_expires_at` in the marker so other
   orchestrators see the PR as actively held, not stale.
4. **Mark ready.** When the phase artifact is complete in the worker's judgment, worker strips the
   marker (releasing the lock) and calls `gh pr ready <M>` — this is the "done" signal.
5. **Human review / merge.** A reviewer (the user, a teammate, or maintainers on OSS) merges the PR.
   Dependent PRs unblock on merge.

## Dependencies (`blocked_by`)

Phases typically chain: `specify` → `design` → `plan` → `implement`* → `release`. Chains are encoded
in the PR body marker's `blocked_by` array — a list of PR numbers in the **same repo** that must
merge before the dependent PR can be marked ready-for-review:

```text
<!-- coordinator = {"lock_owner":"","lock_expires_at":"","blocked_by":[42,57]} -->
```

Rules:

- Dependent PR cannot be marked ready-for-review until every blocker PR is merged. The orchestrator
  pre-screens the frontier; the worker re-checks before flipping draft → ready.
- `implement` often fans out: one `plan` PR may declare several `implement` PRs, each blocked by the
  plan.
- `docs` may run in parallel with `implement` if the API surface is frozen at design time, or may
  block the `release` PR.
- `release` PRs should be blocked-by the full fan of `implement` + `docs` PRs they bundle.

Cross-repo blockers are out of scope for v0.1 — every number in `blocked_by` is resolved against the
same repo as the dependent PR.

The orchestrator dispatches only the unblocked frontier, so the DAG enforces the intended ordering
without human gating between phases.

## Context adaptations

The same PR-phase model works across contexts — only the review bar and the human touchpoints vary.

### Work (team repo)

- `specify` + `design` PRs get team review before `plan` is merged.
- `implement` PRs get the team's normal review process.
- `release` PR is the ship gate — merged by the release owner.

### Personal

- Self-review on each phase. Merge without waiting for a second opinion.
- Optional: fast-forward through `specify`/`design` into `plan` if the work is obvious. Skip phases
  by closing (not merging) an empty PR, or just don't open one.

### Group / collaborative (small team, shared repo)

- Each member runs their own coordinator orchestrator against the same repo list.
- The per-PR marker locks prevent two contributors from picking up the same PR. FIFO isn't needed —
  topological order + locks suffice.
- `specify` / `design` / `plan` PRs are where alignment happens; treat review comments on those PRs
  as the main coordination channel.

### OSS contribution

- You (external contributor) open the `specify` PR on your fork. The maintainer reviews and merges
  into upstream.
- `implement` PRs follow the upstream's conventions for review and signed commits.
- `release` is usually owned by the maintainer; coordinator just makes it easy to see what's
  blocking a release PR at a glance.

## Design principles

The PR-phase model deliberately keeps **all** coordination state on the pull request itself. This
makes the model work:

- **Across machines** — GitHub is the single source of truth. Two contributors on different laptops
  can run orchestrators against the same repo with zero shared filesystem state.
- **Across contexts** — the same workflow works for employer repos, personal side projects, group
  collaborations, and OSS drive-by contributions. Only the review bar changes.
- **Per-PR granularity** — dependencies are expressed as `blocked_by: [PR#, PR#]`, not "phase X must
  finish before phase Y." One `plan` PR can fan out into 12 `implement` PRs, each with their own
  blocker set.
- **Minimal required infra** — `gh` CLI with `repo` scope is all a contributor needs. No shared
  directories, no `.projects/` file, no GitHub Projects v2 board to configure.

The "phase done" signal is the PR's own lifecycle transition (draft → ready-for-review → merged), so
there is no separate status file to keep in sync with reality.

## PR titling convention

`[<phase>] <short description>` (the `phase:<name>` label is authoritative but the prefix makes the
PR list readable).

Examples:

- `[specify] User login flow requirements`
- `[design] Token storage format and rotation`
- `[plan] Split the auth migration into 4 PRs`
- `[implement] 1/4 — JWT validation middleware`
- `[release] v0.4.0 — auth rewrite`
- `[docs] Auth setup guide`
