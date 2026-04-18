---
name: plan-do
scheme: execution
description: Reusable sub-workflow building block — two-step plan → do cycle. Composed by other workflows via `step.workflow: plan-do`; not normally invoked directly but can be (`/workflow run plan-do ...`). Parameterized by `subject`. Produces an implementation-plan document + a code-change PR. Simpler than design-implement-review when the change is small enough to skip explicit design.
contract_version: 1
inputs:
  - { name: 'subject', type: 'string', required: true }
  - { name: 'target_repo', type: 'string', required: true }
  - { name: 'owner', type: 'string', required: true }
---
# plan-do

Reusable 2-step building block — plan → do. Other workflows compose it via
`step.workflow: plan-do`; direct invocation (`/workflow run plan-do ...`) also works but is
uncommon. For larger scope, compose `design-implement-review` instead.
