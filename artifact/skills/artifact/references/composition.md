# composition

Workflows compose other workflows as sub-workflow steps. Composition is the only reuse mechanism —
no inheritance, no overriding, no subclassing.

## Step-level composition

A step whose frontmatter declares `workflow: <name>` spawns the named workflow as a sub-execution
when the parent's walk reaches that step.

```yaml
steps:
  - id: design
    agent: worker
    workflow: write-review
    inputs: { subject: design-document, owner: "{{ owner }}" }
```

At dispatch:

1. The parent worker resolves `write-review` against the registry.
2. The `workflow-execution` artifact template runs with `workflow=write-review` and
   `workflow_inputs={subject, owner}`.
3. A new execution artifact is created. The parent records it in its own `sub_workflow_executions`
   ledger and proceeds.
4. The parent polls the child's `execution.status` until it reports `complete` (or `needs_attention`
   / `aborted`).

## Input mapping

The parent must provide every required input of the child. Unprovided required inputs fail the
dispatch step before the child is spawned — validation happens against the child's declared `inputs`
contract.

Values can be literals, references to the parent's own inputs (`{{ execution.inputs.X }}`), or
outputs of earlier steps in the same parent workflow (`{{ steps.<id>.outputs.<name> }}`).

## Output mapping

A composed step exposes the child workflow's outputs as its own. Other steps in the parent reference
them as `{{ steps.<composed-step>.outputs.<name> }}`.

## Artifact-template composition

Artifact templates are workflows too (the subkind whose outputs are artifacts). Composing an
artifact template works exactly like composing any other workflow — the child runs, produces its
artifact, and the artifact URI comes back as the step's output.

```yaml
steps:
  - id: design
    workflow: write-review                 # artifact template (= workflow)
    inputs: { subject: design-document }
```

The output (an `execution:` URI if run as a normal workflow, or a document URI if the template's
graph wrote through a doc provider) lands in `steps.design.outputs` for later steps to reference.

## Keep sub-workflows small

The clearest composed workflows are shallow: 2–4 steps per level, each step either doing one thing
or composing one small workflow. Deep chains (5+ levels) are legal but hard to read in the dashboard
and hard to resume mid-flight.

## No inheritance

There is no `extends:`, no slot-filling of parent templates, no polymorphic dispatch. If an author
wants a variant, they write a new workflow that composes the same pieces differently. Two small
workflows composed are always cheaper than one `extends:` hierarchy.
