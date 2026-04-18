# workflow-contract

Every workflow file in this plugin ecosystem is a single markdown file whose YAML frontmatter
declares a runnable DAG. This skill documents that schema.

## File shape

```markdown
---
name: <workflow-name>           # unique within its scope
description: <one line>
contract_version: 1
sdlc_phase: [design, implement] # optional: declarative SDLC phase tags
inputs:
  - name: <input-name>
    type: artifact_uri | string | int | bool | ...
    required: true | false
    default: <value>            # optional
    description: <one line>
outputs:
  - name: <output-name>
    type: artifact_uri | ...
    description: <one line>
graph:
  steps:
    - id: <step-id>             # stable, unique within this workflow
      agent: worker              # only role in this plugin
      workflow: <name>          # optional: compose a sub-workflow as this step's body
      prompt_variant: <name>    # optional: worker prompt override
      template: <template-name> # optional: artifact template to produce an artifact
      inputs: { ... }           # optional: inputs passed to the sub-workflow or step body
      gate: { type: review|approve|choose|input, prompt: "..." }  # optional
      when: "<expression>"      # optional: skip the step when the expression is falsy
      pre: { ... }              # optional: preconditions (lint, stash gate, etc.)
  transitions:
    - id: <transition-id>
      from: <step-id>
      to: <step-id>
      metadata: { reasoning: "...", conditional: "llm-judge|...", ... }
dynamic_branches:
  - step: <step-id>
    judge: llm-judge
    transitions: [<transition-id>, ...]
rules:
  tools_allowed: { <step-id>: ["Read", "Edit", ...] }
  tools_denied:  { <step-id>: ["Bash:rm -rf", ...] }
  write_paths_denied: { _all_steps_: [".claude/**", ".github/**"] }
  auto_gate_on:
    - condition: "diff_lines > 500"
      gate: { type: review, prompt: "Large diff — approve?" }
---

# <workflow-name>

Free-form human description. Not loaded by the engine at dispatch; consumed only by the
`conductor` (author) + `review` workflows and the dashboard's detail view.
```

## Invariants the engine enforces

1. `graph.steps[].id` values are unique within the workflow.
2. `graph.transitions[].from` and `.to` reference existing step ids.
3. The DAG is acyclic (cycles in the static graph are rejected at author time; cycles that emerge
   from dynamic-branch judgments are tracked as runtime re-entries, not static loops).
4. `dynamic_branches[].transitions[]` each reference existing transition ids.
5. `inputs[].type` is validated on `/workflow start` — a missing required input fails dispatch fast.
6. Composition (`step.workflow: <name>`) is resolved at dispatch time via the registry; a missing
   sub-workflow causes a hard validation error before any teammate is spawned.
7. `step.when: "<expr>"` evaluates the expression against the workflow's inputs. Truthy → step
   runs; falsy → step is skipped and its outbound transitions fire from the preceding step's `to`
   as if the step were inlined. Allowed expressions: equality (`x == 'v'`), inequality, boolean
   and/or/not, literal `true`/`false`. No side effects; expressions are pure over the inputs bag.

## Conditional steps

Any step may declare `when: "<expression>"`. The expression is evaluated once at dispatch time
against the workflow's declared inputs; there is no re-evaluation after the step would have run.

```yaml
graph:
  steps:
    - id: load
      when: "mode == 'update'"
      ...
    - id: draft
      ...
  transitions:
    - { id: t0, from: load,  to: draft }   # skipped when load is skipped
    - { id: t1, from: draft, to: review }
```

When `load` is skipped, the engine treats `t0`'s outbound target (`draft`) as the start step for
the run. Skipped steps record a `skipped_at` timestamp + the falsy expression in the ledger so
retroactive-diff can reason about them.

## Step signature (used for retroactive-diff)

Every step carries a `step_signature` computed at run time and stored in the execution's step
ledger. Signature = sha256 of:

```text
agent || workflow_ref || sorted(inputs) || sorted(outputs) || template_ref
```

Retroactive-diff compares a stored `step_signature` against the current definition's computed
signature. Mismatch flags the step as `retroactive-changed`; absence flags `retroactive-pending`;
extra flags `orphaned`.

## Scopes

Workflows resolve by scope precedence (highest first):

1. override — `$CWD/.workflow-override/workflows/<name>/SKILL.md`
2. workspace — `$REPO/.claude/workflows/<name>/SKILL.md`
3. user — `~/.claude/workflows/<name>/SKILL.md`
4. plugin    — `<installed-plugin>/skills/workflows/<name>/SKILL.md`

The `conductor` workflow writes only to override/workspace/user scope — never plugin scope (the
`pretooluse-no-self-edit.sh` hook enforces this).

## Validation

`tests/workflow-conformance.sh <path>` parses a workflow file, checks the frontmatter against this
schema, resolves referenced workflows + templates, and exits non-zero on any violation. Run at
authoring time and in CI.
