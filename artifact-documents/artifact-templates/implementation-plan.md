---
name: implementation-plan
scheme: document
description: Fill-in markdown template for implementation plan.
contract_version: 1
inputs:
  - { name: 'title', type: 'string', required: true }
  - { name: 'owner', type: 'string', required: true }
  - { name: 'design_ref', type: 'artifact_uri', required: false }
output_path: docs/plans/{{ slug(title) }}.md
---

---
kind: implementation-plan
title: "{{ title }}"
owner: "{{ owner }}"
design_ref: "{{ design_ref }}"
status: draft
---

## Implementation plan: {{ title }}

### Goal

What this plan will achieve; reference to the design doc.

### Scope

- In scope:
- Out of scope:

### Approach

High-level approach.

### Milestones

- [ ] M1 — ...
- [ ] M2 — ...
- [ ] M3 — ...

### Risks + rollback

Known risks. Rollback plan if something breaks in production.

### Verification

Tests, metrics, user sign-off.
