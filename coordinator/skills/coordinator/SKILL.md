---
name: coordinator
description: >
  Playbook for the `coordinator` orchestrator agent. Scans configured GitHub
  repositories for draft pull requests carrying a `phase:<name>` label
  (PRs only — no issues, no Project v2), builds the `blocked_by` dependency
  graph from each PR's body-marker, computes the unblocked frontier, and
  dispatches up to 3 background worker teammates. Details the dispatch
  loop, hook-driven reconciliation, cron-based stale-lock reclaim, and the
  PR-phase model. Read this at the start of every `/coordinator` pass
  before acting.
---

# coordinator playbook

The orchestrator agent reads this at every invocation. Acts on the sequencing defined here — not
from memory.

## Unit of work: pull requests

PRs are the only unit of work the coordinator tracks. There are no issues, tasks, cards, or
projects. Every phase of the lifecycle — specify, design, plan, implement, release, docs — is a PR:

- **Draft PR** with a `phase:<name>` label = phase is in progress (worker currently holds the lock,
  or paused).
- **Ready-for-review PR** (non-draft) = phase is complete. Worker released the lock when it flipped
  the draft state.
- **Merged / closed PR** = phase artifact has landed.

See `skills/pr-phases/SKILL.md` for the phase model in detail.

## State storage — PR body marker

Per-PR coordination state lives in a single HTML comment line appended to the PR body:

```text
<!-- coordinator = {"lock_owner":"...","lock_expires_at":"...","blocked_by":[...]} -->
```

HTML comments are hidden from rendered Markdown but returned raw by the API. The plugin reads,
splices, and writes back this single line via `gh pr view --json body` and
`gh pr edit --body-file -`. See `skills/lock-protocol/SKILL.md` for the recipes.

## Settings resolution

1. Read `.claude/coordinator.local.md` from the current repo. Extract `repos:` (YAML list of
   `owner/name`) and `default_lease_minutes`.
2. If missing or empty, ask the user once via `AskUserQuestion` and write the answer back to the
   local config file. Never prompt twice per session.
3. Compute `machine_id` once per session: `$(hostname)-$(whoami)-$$`. Compute
   `orchestrator_session_id` as a UUIDv4 (or `date +%s-$$` fallback).

## One pass

Run this sequence on each dispatch trigger (user invocation, TeammateIdle, SubagentStop, TaskStop,
cron tick). A pass is idempotent.

### 1. Scan the repos

`scripts/pr-scan.sh <repo1> <repo2> ...` — returns one JSON record per managed PR:

```json
{
  "repo": "owner/name",
  "number": 12,
  "state": "open",
  "is_draft": true,
  "head_ref_name": "coordinator/specify-login",
  "phase": "specify",
  "lock_owner": "",
  "lock_expires_at": "",
  "blocked_by": []
}
```

A PR is included iff it is open AND carries a `phase:*` label.

### 2. Normalize lock state

For each PR: if `lock_expires_at != ""` and `lock_expires_at < now_iso` (ISO-8601 string compare),
treat as unlocked (`lock_owner` logically empty). Never *clear* the expired marker here — the next
worker's acquire will overwrite it.

### 3. Filter dispatchable PRs

A PR is dispatchable when:

- `state == "open"`
- `is_draft == true` (ready-for-review PRs are awaiting human review, not worker attention)
- `lock_owner` empty (after stale normalization)
- Every PR number in `blocked_by` resolves to a PR in the same repo whose `state == "merged"` (check
  via `gh pr view <N> --json state --repo ...` when needed; skip PRs where a blocker is `open` or
  `closed-unmerged`).

### 4. Topological pick (no FIFO)

Dispatchable PRs form the unblocked frontier of the DAG. When frontier size exceeds free worker
slots, pick by `number` ascending (stable tiebreak).

### 5. Dispatch

For each free worker slot (max 3) paired with a frontier PR:

- Agent-teams teammate spawn — role `coordinator-worker`.
- Initial `SendMessage` payload:

  ```json
  {
    "pr_number": <M>,
    "repo": "<owner/name>",
    "phase": "<phase>",
    "title": "<PR title>",
    "expected_work_minutes": <default_lease_minutes>
  }
  ```

- Do **not** write a lock yourself — the worker acquires it on first action.

### 6. Register reconciliation triggers (first pass only)

On the first pass of a session:

- `CronCreate` — recurring 1-min cron firing `/coordinator rescan`. Store its id.
- Hooks are pre-registered by the plugin manifest — no action needed here.

On session end (`/coordinator stop` or exit): `CronDelete` the stored id.

### 7. Handle worker replies

Worker `SendMessage`s you receive look like:

| `status`   | Meaning                          | Action                                                      |
|------------|----------------------------------|-------------------------------------------------------------|
| `raced`    | Another worker locked it first   | Dispatch next frontier PR to this teammate                  |
| `question` | Worker needs user input          | `AskUserQuestion` with relayed payload; reply via `SendMessage` |
| `done`     | Worker finished PR               | Re-run one pass; freed teammate will pick up next           |
| `error`    | Worker hit a fatal error         | Surface to user; lock already released by stop hook         |

### 8. Relay worker questions

When a worker sends `{status: "question", text, options}`:

- Present via your `AskUserQuestion` with the exact `text` and `options`.
- On user answer, `SendMessage` the worker: `{answer: <selected label or free text>}`.
- Do not drop messages; keep relay turnaround short.

### 9. Opening new phase PRs on demand

When the user asks the orchestrator to "start a specify / design / plan / implement / release / docs
PR for X":

- Use `AskUserQuestion` to confirm the title, repo, and any `blocked_by` PR numbers.
- Drive `scripts/ensure-pr.sh --repo ... --phase ... --title ...` yourself (not from a worker). This
  creates the draft PR and attaches the `phase:<phase>` label.
- If `blocked_by` is non-empty, open the PR then immediately call `scripts/lock-acquire.sh` with our
  owner string to stamp the marker, then `scripts/lock-release.sh` to release — but with
  `blocked_by` preserved. (Shortcut: set `blocked_by` in the initial marker during the same write.)
- On the next pass a worker picks it up.

## Never

- Dispatch more than 3 workers concurrently per orchestrator.
- Dispatch to a PR with `lock_expires_at > now` and non-empty `lock_owner`.
- Create or update GitHub issues — PRs only.
- Use GitHub Projects (v2 or otherwise).
- Clear another orchestrator's lock directly. Only the owning worker or its stop hook releases.
- Use the Task tool. Teammate dispatch only.
- Persist state to disk — GitHub is the source of truth.

## References

- `scripts/pr-scan.sh` — scan repos for managed PRs.
- `scripts/ensure-pr.sh` — open or resolve a draft PR for a phase.
- `scripts/lock-acquire.sh` / `lock-release.sh` / `lock-heartbeat.sh` — worker-side marker ops; read
  for understanding.
- `skills/lock-protocol/SKILL.md` — body-marker recipes and race mitigation.
- `skills/pr-phases/SKILL.md` — the PR-phase model.
