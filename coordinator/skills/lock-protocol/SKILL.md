---
name: lock-protocol
description: >
  Recipes for acquiring, heartbeating, and releasing the coordinator lock on
  a pull request by splicing a single HTML-comment marker into the PR body.
  Includes race mitigation via read-back verification and the stale-lock
  reclaim rule. Used by the `coordinator` orchestrator and
  `coordinator-worker` agent. PRs are the only locked resource — no issues,
  no projects.
---

# Lock protocol

GitHub is the single source of truth. Every coordinator-managed PR carries a single HTML-comment
marker line at the end of its body:

```text
<!-- coordinator = {"lock_owner":"<machine>:<session>:<worker>","lock_expires_at":"2026-04-16T18:45:00Z","blocked_by":[42,57]} -->
```

Fields:

| Field             | Type          | Meaning                                                                |
|-------------------|---------------|------------------------------------------------------------------------|
| `lock_owner`      | string        | `<machine>:<orchestrator-session>:<worker-agent>`. Empty = unlocked.  |
| `lock_expires_at` | ISO-8601 UTC  | Absolute expiry (e.g. `2026-04-16T18:45:00Z`). Lex-compares as time.  |
| `blocked_by`      | list[int]     | PR numbers in the same repo that must merge before this PR can ready. |

Rationale:

- HTML comments are stripped by Markdown rendering but served raw by the GitHub API, so users never
  see the marker.
- ISO-8601 Zulu UTC sorts lexicographically in the same order as by actual time, so `string compare`
  is a valid expiry check.
- One marker line per PR — the plugin only touches that line; user-authored body above it is
  preserved.

## Acquire

Called by the worker once per assignment for its PR.

```bash
scripts/lock-acquire.sh \
  --repo   <owner/name> \
  --pr     <N> \
  --owner  "<machine>:<session>:<worker>" \
  --expires-at "$(date -u -v+15M +'%Y-%m-%dT%H:%M:%SZ')"
```

Under the hood:

1. `gh pr view <N> --repo <R> --json body -q .body` — read current body.
2. Extract the marker line with regex `^<!-- coordinator = (\{.*\}) -->$`. Missing → treat as
   unlocked.
3. If `lock_owner` non-empty AND `lock_expires_at > now_iso` AND `lock_owner != $OWNER`, another
   worker holds it. Exit 1.
4. Build a new marker: `lock_owner = $OWNER`, `lock_expires_at = $EXPIRY`, preserve existing
   `blocked_by`.
5. Write body: strip any existing marker line; append the new marker on a fresh line (separated by a
   blank line from user content). Pipe through `gh pr edit <N> --repo <R> --body-file -`.
6. Race mitigation: 100–500ms random delay, re-read body, re-extract marker, confirm
   `lock_owner == $OWNER`. If not, release our half-write via `lock-release.sh` and exit 1.

## Heartbeat

```bash
scripts/lock-heartbeat.sh \
  --repo <owner/name> \
  --pr   <N> \
  --expected-owner "<machine>:<session>:<worker>" \
  --expires-at "$(date -u -v+15M +'%Y-%m-%dT%H:%M:%SZ')"
```

Read current body. If marker missing OR `lock_owner != expected`, exit 1 (lock stolen). Otherwise
write a fresh marker with the same `lock_owner` and new `lock_expires_at`. `blocked_by` is
preserved.

## Release

```bash
scripts/lock-release.sh --repo <owner/name> --pr <N>
# Or, for the SubagentStop hook path:
scripts/lock-release.sh --repo <owner/name> --pr <N> --expected-owner "<string>"
```

Reads the body, strips the marker line (and trailing blank line left behind), writes back.
Idempotent: if no marker is present, it's a no-op that reports
`{"released": false, "reason": "no-marker"}`.

`--expected-owner` makes release conditional: only strip if the current `lock_owner` matches. Used
by `hooks/release-lock-on-stop.sh` so a crashed worker doesn't nuke a fresh worker's newly-acquired
lock.

## Stale reclaim

Orchestrator during scan treats `lock_expires_at < now_iso` (string compare on Zulu ISO-8601) as
*logically unlocked* but does **not** strip the marker. The next worker's acquire overwrites both
`lock_owner` and `lock_expires_at` in a single write, atomically from their perspective.

## Concurrent body edits (user or bot)

The read-splice-write cycle is best-effort. If a human edits the PR body between our read and write,
we may overwrite their change. Mitigations:

- Keep the window tight — one `gh pr view` immediately before one `gh pr edit`.
- The plugin only touches the marker line; the rest of the body is preserved verbatim.
- Document in the README that coordinator-managed PRs should not have their bodies edited during
  active dispatch.

## Never

- Clear another worker's lock directly. Only the owning worker (or its stop hook with
  `--expected-owner`) releases.
- Acquire without reading first — always read-then-write-then-read-back.
- Store the lock start time. Only the absolute expiration lives in GitHub; the start time is visible
  in the PR's edit history.
- Heartbeat after a worker has reported `done` — release is terminal.
- Lock any resource other than a PR. Issues, drafts, and discussions are out of scope.
- Use GitHub Projects or any project-level custom fields.
