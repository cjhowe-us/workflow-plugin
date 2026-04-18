---
name: plan-do
description: |-
  Base workflow — a reusable 2-step plan → do building block other workflows compose via `step.workflow: plan-do`. Direct invocation (`/workflow run plan-do ...`) is allowed but uncommon; this flow is meant to be inlined into larger workflows. Parameterized by `subject`; produces an implementation-plan document + a code-change PR.
---

# plan-do

A compact 2-step building block: **plan → do**. Intended for composition inside larger workflows
that need a small, well-understood change. For larger scope, compose `design-implement-review`
instead.

## Composition

Other workflows reference `plan-do` via:

```yaml
graph:
  steps:
    - id: do-the-thing
      workflow: plan-do
      inputs:
        subject: "the thing"
        target_repo: "{{ target_repo }}"
        owner: "{{ owner }}"
```

The engine resolves `plan-do` via the workflow registry + scope precedence, validates inputs
against its manifest, and runs it as a sub-workflow on its own worktree. The parent gets a
`composed_of` edge to the child execution.

## Direct invocation

Also allowed: `/workflow run plan-do --subject ... --target_repo ... --owner ...`. Useful for
one-off use and for smoke-testing the workflow in isolation.
