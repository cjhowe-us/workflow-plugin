# workflow

Workflow primitive for the artifact ecosystem. Ships the worker agent, orchestration hooks, the
`execution` scheme + `execution-gh-pr` backend, the `/workflow` entry skill, the
`workflow-execution` artifact template (the bootstrap that turns a workflow definition into a
live execution), and four base workflows:

- **`default`** — orchestrator + dashboard. Entry point for every `/workflow` invocation.
- **`conductor`** — the single meta-workflow: a workflow that creates/edits/reviews/deletes
  other workflows and artifact templates. Four modes (`create` / `update` / `review` /
  `delete`) dispatched via conditional steps on the `mode` input.
- **`plan-do`** — reusable 2-step (plan → do) building block composed by other workflows.
- **`write-review`** — reusable 2-step (write → review) building block composed by other
  workflows.

Depends on the [`artifact`](https://github.com/cjhowe-us/artifact) plugin.

## Install

```bash
claude plugin marketplace add cjhowe-us/marketplace
claude plugin install artifact@cjhowe-us-marketplace   # required
claude plugin install workflow@cjhowe-us-marketplace
```

## Prerequisites

- `gh` CLI, authenticated (`gh auth login`). Identity comes from `gh auth status` — no login
  dialog.
- `git` ≥ 2.30 (worktrees).
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment. The `env-setup` plugin can
  persist this.

## First run

`/workflow` opens the dashboard and routes user intent. On first invocation the `default`
orchestrator runs its tutor: welcome, the workflow/artifact primitives, installed extensions,
and a guided try-it.

## Extending with your own workflows

**User extensibility is the whole point.** You don't fork the plugin to add a workflow — you
drop files into one of four scope directories. Discovery walks all four at session start and
the registry picks them up automatically.

| Scope       | Path                                                            | Purpose                                    |
|-------------|-----------------------------------------------------------------|--------------------------------------------|
| `override`  | `$CWD/.artifact-override/workflows/<name>/`                     | One-off; for this working tree only        |
| `workspace` | `$REPO/.claude/workflows/<name>/`                               | Project-specific; commit to the repo       |
| `user`      | `~/.claude/workflows/<name>/`                                   | Personal; shared across all your projects  |
| `plugin`    | `<installed-plugin>/skills/workflows/<name>/`                   | Shipped by a plugin; immutable             |

Precedence: override > workspace > user > plugin. A workspace-scope workflow named `default`
will shadow this plugin's `default`.

**Author the easy way:**

```text
/workflow create <name> --scope workspace      # commit to $REPO/.claude/workflows/
/workflow create <name> --scope user            # live under ~/.claude/workflows/
/workflow create <name> --scope override        # transient in $CWD/.artifact-override/
```

This dispatches the `conductor` workflow in `mode: create`; it prompts for inputs/outputs/step
graph, validates with `workflow-conformance.sh`, and writes. Same command structure covers
updates (`/workflow update <uri>`), reviews (`/workflow review <uri>`), and deletions
(`/workflow delete <uri>`) — all drive through conductor's mode switch.

Each workflow directory holds a `SKILL.md` (Claude Code skill frontmatter: `name`,
`description` + prose body) and a `manifest.json` (structured DSL: inputs, outputs, graph,
transitions, dynamic_branches). See
[`skills/workflow/references/workflow-contract.md`](skills/workflow/references/workflow-contract.md)
for the full schema.

**Artifact templates follow the same rules** — put project-specific templates under
`$REPO/.claude/artifact-templates/<name>.md`, personal templates under
`~/.claude/artifact-templates/<name>.md`. Discovery picks them up.

**Gitignore reminder:** `~/.claude/` is per-user; don't commit it to a project repo. But
committing `$REPO/.claude/` is exactly what workspace scope is for — check it in.

## Files

- `agents/worker.md` — the single agent role.
- `hooks/` — env check, orchestrator lock, PreToolUse rules, PostToolUse progress, SubagentStop
  release, TeammateIdle rescan, UserPromptSubmit status. Session-start discovery lives in the
  artifact plugin.
- `scripts/orchestrator-lock.sh` — per-machine flock. `scripts/dispatch-execution.sh` — shared
  helper used by workflow-shape templates to instantiate an execution artifact.
- `skills/workflow/` — `/workflow` entry skill. References under `references/` load on demand.
- `skills/workflows/` — four base workflows: `default`, `conductor`, `plan-do`, `write-review`.
- `artifact-templates/workflow-execution.md` — the bootstrap template (`/workflow run` goes
  through this).
- `artifact-providers/execution/` + `artifact-backends/execution-gh-pr/` — the `execution`
  scheme and its GitHub-PR-backed backend.
- `tests/workflow-conformance.sh`.
- `DESIGN.md` — workflow-side design doc + dated changelog.

## Dogfooding

The workflow plugin is a reference plugin for the artifact plugin:

- Every artifact call goes through `artifact/scripts/run-provider.sh`.
- Workflow state lives as artifacts (the `execution` scheme) managed by the artifact plugin.
- The `conductor` workflow drives CRUD on workflows + templates entirely through the artifact
  plugin's subcommand surface (`create` / `get` / `update` / `delete`).

If any cross-plugin link needs a special case, fix the artifact contract — not the consumer.

## Not supported

- Writing under any installed plugin's root (blocked by `pretooluse-no-self-edit.sh`). To
  change a built-in workflow, copy it to workspace/user/override scope or open a PR to the
  plugin repo.
- Automatic transfer of artifact locks. Ownership changes are manual (e.g. reassigning a PR
  on GitHub).

## License

Apache-2.0.
