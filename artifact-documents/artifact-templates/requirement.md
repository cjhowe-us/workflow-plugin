---
name: requirement
scheme: document
description: Fill-in markdown template for requirement.
contract_version: 1
inputs:
  - { name: 'id', type: 'string', required: true }
  - { name: 'title', type: 'string', required: true }
  - { name: 'priority', type: 'string', required: false, default: 'p2' }
output_path: docs/requirements/{{ id }}.md
---

---
kind: requirement
id: "{{ id }}"
title: "{{ title }}"
priority: "{{ priority }}"
---

## {{ id }} — {{ title }}

### Goal

What outcome this requirement achieves, stated as a user-visible benefit.

### Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### Constraints

Platform, compatibility, performance, or UX constraints the implementation must honor.

### Out of scope

What this requirement intentionally does not cover.

### Linked artifacts

- Design: <design_ref>
- User story: <user_story_ref>
