---
name: test-plan
scheme: document
description: Fill-in markdown template for test plan.
contract_version: 1
inputs:
  - { name: 'title', type: 'string', required: true }
  - { name: 'owner', type: 'string', required: true }
  - { name: 'design_ref', type: 'artifact_uri', required: false }
output_path: docs/test-plans/{{ slug(title) }}.md
---

---
kind: test-plan
title: "{{ title }}"
design_ref: "{{ design_ref }}"
owner: "{{ owner }}"
---

## Test plan: {{ title }}

### Strategy

Unit / integration / e2e / manual coverage balance.

### Cases

| id | description | expected | status |
|----|-------------|----------|--------|
| tc1 | ... | ... | pending |

### Oracles

How we determine pass/fail when output isn't trivially comparable.

### Environments

Where these tests run (CI, staging, local).

### Exit criteria

When is this plan done.
