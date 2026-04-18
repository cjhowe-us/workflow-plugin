---
name: workflow-execution
scheme: execution
description: The one artifact template that turns a workflow definition into a live workflow-execution artifact. Single step — instantiate — calls `execution.create` via the configured provider (default gh-pr) with the workflow's inputs and the owning GitHub user. Invoked by `/workflow start <workflow>` and by every step in every other workflow that composes a sub-workflow.
contract_version: 1
inputs:
  - { name: 'workflow', type: 'workflow_ref', required: true, description: 'URI or name of the workflow definition to run.' }
  - { name: 'workflow_inputs', type: 'json', required: false, description: "Map of inputs to pass to the workflow. Validated against the workflow's declared inputs." }
  - { name: 'parent_execution', type: 'artifact_uri', required: false, description: 'Parent execution URI when this is a sub-workflow dispatch.' }
  - { name: 'target_repo', type: 'string', required: false, description: '<owner>/<repo>. Required when the execution provider needs it (gh-pr default does).' }
  - { name: 'owner', type: 'string', required: false, description: 'GH user taking ownership. Defaults to `gh auth` user.' }
---

---
name: workflow-execution
description: The one artifact template that turns a workflow definition into a live workflow-execution artifact. Single step — instantiate — calls `execution.create` via the configured provider (default gh-pr) with the workflow's inputs and the owning GitHub user. Invoked by `/workflow start <workflow>` and by every step in every other workflow that composes a sub-workflow.
contract_version: 1
sdlc_phase: [dispatch]
inputs:
  - { name: workflow,    type: workflow_ref, required: true,  description: "URI or name of the workflow definition to run." }
  - { name: workflow_inputs, type: json,     required: false, description: "Map of inputs to pass to the workflow. Validated against the workflow's declared inputs." }
  - { name: parent_execution, type: artifact_uri, required: false, description: "Parent execution URI when this is a sub-workflow dispatch." }
  - { name: target_repo, type: string,       required: false, description: "<owner>/<repo>. Required when the execution provider needs it (gh-pr default does)." }
  - { name: owner,       type: string,       required: false, description: "GH user taking ownership. Defaults to `gh auth` user." }
outputs:
  - { name: execution,   type: artifact_uri, description: "Newly-created workflow-execution artifact." }
graph:
  steps:
    - id: instantiate
      agent: worker
      prompt_variant: dispatcher
      description: "Resolve workflow; validate workflow_inputs against the workflow's inputs contract; call `execution.create` via the configured provider with the rendered payload; return the URI."
  transitions: []
---

# workflow-execution

Canonical entry to run a workflow. Every start path — user-invoked or orchestrator-internal — goes
through this template so execution instantiation has exactly one implementation to maintain.

## What `instantiate` does

1. Resolve the workflow reference to a concrete workflow file via the registry (respecting scope
   precedence).
2. Load the workflow's `inputs` contract; validate `workflow_inputs` against it. Reject with a
   blocker on missing required or wrong-type.
3. Derive the new execution's identity: `exec-<ulid>` under the parent's execution path if
   `parent_execution` is set, otherwise at root.
4. Compute the per-step ledger seed: for each step in the workflow, prepare an empty ledger entry
   with the `step_signature` pre-computed (so retroactive-diff can work later).
5. Call the `execution` provider's `create` with a payload containing the workflow name, rendered
   inputs, owner, parent, and seeded ledger. The provider opens the underlying backend artifact
   (default: GitHub PR) and returns the URI.
6. Return `execution:<uri>` as the step's output for the caller.

## Why this is a template, not baked into the orchestrator

The retroactive-diff, multi-dev, and bidirectional-sync invariants all rely on executions being
artifacts with a uniform lifecycle. Keeping instantiation in an artifact template means the path is
the same for user-initiated starts, sub-workflow dispatch, and programmatic invocation — one set of
validation rules, one ledger shape, one observer surface.
