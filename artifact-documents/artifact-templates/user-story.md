---
name: user-story
scheme: document
description: Fill-in markdown template for user story.
contract_version: 1
inputs:
  - { name: 'id', type: 'string', required: true }
  - { name: 'title', type: 'string', required: true }
  - { name: 'persona', type: 'string', required: true }
  - { name: 'want', type: 'string', required: true }
  - { name: 'benefit', type: 'string', required: true }
output_path: docs/user-stories/{{ id }}.md
---

---
kind: user-story
id: "{{ id }}"
title: "{{ title }}"
---

## {{ id }} — {{ title }}

### Story

As a **{{ persona }}**, I want **{{ want }}**, so that **{{ benefit }}**.

### Acceptance

- [ ] Given ..., When ..., Then ...
- [ ] Given ..., When ..., Then ...

### Notes

Context, links, caveats.
