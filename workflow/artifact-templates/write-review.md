---
name: write-review
scheme: execution
description: Reusable sub-workflow building block — write an artifact, then review it, with an optional redo loop. Composed by other workflows via `step.workflow: write-review`; not normally invoked directly but can be (`/workflow run write-review ...`). Parameterized by `subject` (what kind of artifact). Produces one document artifact.
contract_version: 1
inputs:
  - { name: 'subject', type: 'string', required: true }
  - { name: 'owner', type: 'string', required: true }
  - { name: 'context', type: 'artifact_uri', required: false }
---
# write-review

Reusable 2-step building block — write → review, with a redo loop if the reviewer requests
changes. Other workflows compose it via `step.workflow: write-review`; direct invocation
(`/workflow run write-review --subject design-document`) also works but is uncommon.
