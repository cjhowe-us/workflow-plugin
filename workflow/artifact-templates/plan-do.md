---
name: plan-do
scheme: execution
description: Two-step cycle — plan the work, then do it. Parameterized by `subject`. Produces an implementation-plan document as plan-phase output and a code-change PR as do-phase output. Composable. Simpler than design-implement-review when the change is small enough to skip explicit design.
contract_version: 1
inputs:
  - { name: 'subject', type: 'string', required: true }
  - { name: 'target_repo', type: 'string', required: true }
  - { name: 'owner', type: 'string', required: true }
---

---
name: plan-do
description: Two-step cycle — plan the work, then do it. Parameterized by `subject`. Produces an implementation-plan document as plan-phase output and a code-change PR as do-phase output. Composable. Simpler than design-implement-review when the change is small enough to skip explicit design.
contract_version: 1
sdlc_phase: [plan, implement]
inputs:
  - { name: subject,      type: string,       required: true }
  - { name: target_repo,  type: string,       required: true }
  - { name: owner,        type: string,       required: true }
outputs:
  - { name: plan,         type: artifact_uri, description: "Implementation plan document." }
  - { name: change,       type: artifact_uri, description: "PR containing the code change." }
graph:
  steps:
    - id: plan
      agent: worker
      prompt_variant: author
      template: implementation-plan
      description: "Author an implementation plan for the subject."
    - id: do
      agent: worker
      prompt_variant: implementer
      gate: { type: review, prompt: "Approve the plan before coding starts?" }
      description: "Implement against the plan; open a PR with the changes."
  transitions:
    - { id: t1, from: plan, to: do }
---

# plan-do

A compact loop for small, well-understood work. For larger scope, compose `design-implement-review`
instead.
