# coordinator

Interactive orchestrator plugin for Claude Code. Dispatches up to 3 background worker teammates to
work in parallel on GitHub pull requests whose dependencies are resolved. Multiple users — each on
their own machine, each running their own orchestrator — coordinate through GitHub pull requests
themselves. No shared filesystem, no GitHub Projects, no project setup.

## What it does

- Scans configured GitHub repositories for **draft pull requests carrying a `phase:<name>` label**.
  PRs are the only unit of work; there are no issues, tasks, cards, or project items in this model.
  Every phase of software work (specify / design / plan / implement / release / docs) is a PR. See
  `skills/pr-phases/SKILL.md` for the full model.
- Reads each PR's body-marker `blocked_by` list to build the dependency DAG. A dependent PR only
  becomes a dispatch candidate once every blocker PR in its `blocked_by` is merged.
- For every PR in the unblocked frontier, dispatches a worker (agent-teams teammate) that splices a
  coordinator HTML-comment marker into the PR body (the lock), works in an isolated git worktree on
  the PR's branch, heartbeats the marker's `lock_expires_at`, then strips the marker on finish or
  crash.
- Workers run as **background** teammates and cannot prompt the user directly. They `SendMessage`
  the orchestrator with any blocking question; the orchestrator calls `AskUserQuestion` on its own
  interactive turn and relays the answer back.

## Requirements

- Claude Code with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set.
  **Required — the plugin's `SessionStart` hook blocks the session with exit 2 if this is not set.**
  This plugin **depends on `env-setup`** (same marketplace) to persist the variable cross-platform.
- `gh` CLI authenticated with the `repo` scope (sufficient to read/write PR bodies and labels). No
  `project` / `read:project` scopes needed.
- One or more GitHub repositories that the authenticated user can edit.
- The `env-setup` plugin (listed in the same marketplace.json — install together).

### Persisting `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`

From Claude Code, invoke the env-setup skill:

```text
/env-setup:env-setup CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1
```

Or drive the scripts directly:

```bash
# bash / zsh / fish / sh
env-setup/skills/env-setup/scripts/ensure-env.sh \
  --var CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS --value 1
```

```powershell
# PowerShell — HKCU:\Environment registry on Windows, $PROFILE elsewhere
pwsh -NoProfile -File env-setup/skills/env-setup/scripts/ensure-env.ps1 `
  -VarName CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -VarValue 1
```

`env-setup` detects your shell and writes to the right config for your platform (see
`env-setup/README.md` for the supported matrix).

## State storage — per-PR body marker

The coordinator writes a single HTML-comment marker at the end of every PR it manages:

```text
<!-- coordinator = {"lock_owner":"<machine>:<session>:<worker>","lock_expires_at":"2026-04-16T18:45:00Z","blocked_by":[42,57]} -->
```

HTML comments are stripped by GitHub's Markdown renderer but returned raw through the API, so the
marker is invisible to humans reading the PR while still being machine-readable. The plugin only
touches this single line; the user-authored body above it is preserved.

> **Don't edit the marker line manually during active dispatch.** If you need to edit the PR body
> while a worker is running, pause the orchestrator first (or let the lock expire) to avoid a race
> that might overwrite your edit.

## Configuration

Per-user local config at `.claude/coordinator.local.md`:

```markdown
---
repos:
  - cjhowe-us/coordinator-sandbox
  - cjhowe-us/workflow
default_lease_minutes: 15   # how long a newly-acquired lock lasts
---
```

The `repos:` list is the scan scope. Any draft PR in one of these repos that carries a
`phase:<name>` label is considered managed.

## Usage

```text
claude --agent coordinator
```

Or invoke the `/coordinator` skill from within a Claude Code session.

The orchestrator runs as an **interactive-only** agent (`disable-model-invocation: true`) — it
cannot be spawned automatically by other agents.

## Environment overrides

| Variable                                    | Default | Purpose                                                        |
|---------------------------------------------|---------|----------------------------------------------------------------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`      | —       | Must be `1`. Enables agent-teams worker dispatch.              |
| `COORDINATOR_UNBLOCK_HOOK_DEBOUNCE_SEC`     | `30`    | Debounce window for the unblock-scan hook to avoid thrash.     |

## Testing

**Script parity (cross-platform):**

```bash
pwsh -NoProfile -File coordinator/tests/test-parity.ps1
```

Fails CI when a `.sh` lacks a sibling `.ps1` (or vice versa) or a `.ps1` has a syntax error.

**Script smoke tests:**

```bash
cd coordinator/tests
python3 -m pytest -v
```

A Python shim on `PATH` fakes the subset of `gh` the plugin uses (`pr list`, `pr view`, `pr edit`,
`pr create`, `label create`, `repo view`) against an in-memory repo map. Offline — no network, no
API key.

End-to-end behavior of the orchestrator is verified the same way users run it: start a Claude Code
session with `claude --agent coordinator`, point it at a test repo, and observe the dispatch
directly in that conversation.

See `/Users/cjhowe/.claude/plans/the-idea-is-that-delightful-fiddle.md` for the overall verification
plan.
