# authoring

Shared plumbing for meta-workflows that create or edit workflows. Artifact templates are workflows
too (a subkind); no separate authoring path for them. Three capabilities:

1. **Resolve** a target path for a new or existing workflow by `(scope, role, name)`, where `role`
   is `workflows` for runnable workflows or `artifact-templates` for the subkind used as template
   generators.
2. **Validate** a candidate file against the `workflow-contract`.
3. **Write** it out, refusing any path under a plugin root.

## Scope resolution

| Scope     | Target path (role = workflows)                      |
|-----------|------------------------------------------------------|
| override  | `$CWD/.workflow-override/workflows/<name>/SKILL.md`  |
| workspace | `$REPO/.claude/workflows/<name>/SKILL.md`            |
| user      | `$HOME/.claude/workflows/<name>/SKILL.md`            |

Replace `workflows` with `artifact-templates` when the workflow's role is to generate artifacts.
Role is a directory-layout hint only — the file shape and contract are identical. Plugin scope is
never a write target (enforced by `pretooluse-no-self-edit.sh`).

## Validation

Before any write, the authoring skill must invoke `tests/workflow-conformance.sh <path>` (or the
template variant) and refuse to write a file that fails validation. Validation errors surface as
plain blockers to the user so the meta-workflow can prompt for corrections interactively.

## Write refusal under plugin roots

All writes go through a path guard that rejects any target under an installed plugin's root.
Double-enforced by the `PreToolUse` hook as a backstop; the skill's own refusal path gives a cleaner
error message before the hook ever fires.

## Flow for `author` meta-workflow

1. **draft** step: collect name, description, inputs/outputs, graph via `AskUserQuestion`.
2. **review** step: render the draft, allow edits, run conformance check.
3. **write** step: resolve target path from chosen scope, write the file, re-run conformance on the
   committed version.

Each step in the meta-workflow writes its partial artifact to the execution provider so the draft
survives session restarts and can be resumed.

## Flow for `update`

1. **load** step: resolve URI to a concrete file path (respects scope precedence). Refuse if path
   resolves to plugin scope.
2. **edit** step: apply the user's edit instructions to the file contents.
3. **write** step: conformance check, then write + verify.

## Flow for `review`

1. **load** — resolve URI + read file.
2. **critique** — run conformance + heuristic checks (naming, step-id uniqueness, input/output
   coverage, dynamic-branch reachability).
3. **report** — emit findings as a set of suggested edits. Never writes.

## Provider integration

Authoring meta-workflows use the `file-local` artifact provider for writes. That provider's
`create`/`update`/`get` are the transport; it takes care of locking and progress logging.
