---
name: write-review
description: |-
  Base workflow — a reusable 2-step write → review building block with an optional redo loop. Composed by other workflows via `step.workflow: write-review`. Direct invocation (`/workflow run write-review ...`) is allowed but uncommon. Parameterized by `subject` (what kind of artifact); produces one document artifact.
---

# write-review

A compact 2-step building block: **write → review**, with a redo loop if the reviewer requests
changes. Intended for composition inside larger workflows.

## Composition

```yaml
graph:
  steps:
    - id: author-design
      workflow: write-review
      inputs:
        subject: "design-document"
        owner: "{{ owner }}"
        context: "{{ context_uri }}"
```

The engine resolves `write-review` via the registry + scope precedence, validates inputs, and
runs it as a sub-workflow on its own worktree. The parent gets a `composed_of` edge to the
child execution.

## Direct invocation

`/workflow run write-review --subject design-document --owner <user>` — allowed for one-off use.
