---
name: design-document
scheme: document
description: Fill-in markdown template for design document.
contract_version: 1
inputs:
  - { name: 'title', type: 'string', required: true }
  - { name: 'author', type: 'string', required: true }
output_path: docs/design/{{ slug(title) }}.md
---

---
kind: design-document
title: "{{ title }}"
authors: ["{{ author }}"]
status: draft
related_artifacts: []
---

## {{ title }}

### Context

Why this design is needed, what prompted it, and the intended outcome.

### Goals

- Goal 1
- Goal 2

### Non-goals

- Non-goal 1
- Non-goal 2

### Design

Description of the proposed change.

#### Interfaces

Public APIs, module boundaries, data shapes.

#### Key decisions

Decisions worth calling out (and the alternatives considered).

### Risks

Known risks + proposed mitigations.

### Verification

How we'll know the design works in practice — tests, metrics, user behavior.

### Open questions

- Question 1
- Question 2
