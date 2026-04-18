# workflow

Workflow primitive for the artifact ecosystem. Ships the worker agent, orchestration hooks, the execution artifact
provider, the `/workflow` entry skill, three workflow-shape artifact templates (write-review, plan-do,
workflow-execution), and four meta-workflows (default, author, review, update).

Depends on the [`artifact`](../artifact) plugin for the artifact / template / provider primitives.

## Install

```bash
claude plugin marketplace add cjhowe-us/workflow
claude plugin install artifact@cjhowe-us-workflow         # required
claude plugin install workflow@cjhowe-us-workflow         # this plugin
claude plugin install artifact-github@cjhowe-us-workflow  # recommended: GH providers
claude plugin install artifact-documents@cjhowe-us-workflow  # recommended: doc templates
claude plugin install workflow-sdlc@cjhowe-us-workflow    # optional: SDLC cycles
```

## Prerequisites

- `gh` CLI, authenticated (`gh auth login`). Identity comes from `gh auth status` — no login dialog.
- `git` ≥ 2.30 (worktrees).
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment. The `env-setup` plugin can persist this.

## First run

`/workflow` opens the dashboard and routes user intent. On first invocation the `default` orchestrator runs its tutor:
welcome, the workflow/artifact primitives, installed extensions, and a guided try-it.

## Files

- `agents/worker.md` — the single agent role.
- `hooks/` — env check, orchestrator lock, PreToolUse rules, PostToolUse progress, SubagentStop release, TeammateIdle
  rescan, UserPromptSubmit status. Session-start discovery lives in the artifact plugin.
- `scripts/orchestrator-lock.sh` — per-machine flock. `scripts/dispatch-execution.sh` — shared helper used by
  workflow-shape templates to instantiate an execution artifact.
- `skills/workflow/` — `/workflow` entry skill. References under `references/` load on demand.
- `skills/workflows/` — `default`, `author`, `review`, `update` meta-workflows.
- `artifact-templates/` — `write-review`, `plan-do`, `workflow-execution`. Directory-per- template (manifest.json +
  TEMPLATE.md + instantiate.sh).
- `artifact-providers/execution/` — the workflow-domain execution provider. Default backend is a GitHub PR (body +
  comments).
- `tests/workflow-conformance.sh`.
- `DESIGN.md` — workflow-side design doc + dated changelog.

## Dogfooding

The workflow plugin is itself a reference plugin for the artifact plugin:

- Every provider call goes through `artifact/scripts/run-provider.sh`.
- Every template instantiation goes through `artifact/scripts/instantiate-template.sh`.
- The workflow-shape templates shipped here are read and executed by the artifact plugin's template subsystem.

If any cross-plugin link needs a special case, fix the artifact contract — not the consumer.

## Not supported

- Writing under any installed plugin's root (blocked by `pretooluse-no-self-edit.sh`). To change a built-in workflow,
  copy it to workspace/user/override scope or open a PR to the plugin repo.
- Automatic transfer of artifact locks. Ownership changes are manual (e.g. reassigning a PR on GitHub).
- Preserving v1 `coordinator` data. v2 is a fresh install; re-open any open PRs under the new conventions.

## License

Apache-2.0.
