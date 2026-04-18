---
name: release-note
scheme: document
description: Fill-in markdown template for release note.
contract_version: 1
inputs:
  - { name: 'version', type: 'string', required: true }
  - { name: 'released_at', type: 'string', required: true }
output_path: docs/releases/{{ version }}.md
---

---
kind: release-note
version: "{{ version }}"
released_at: "{{ released_at }}"
---

# Release {{ version }}

## Highlights

One-paragraph summary for users.

## Breaking changes

- (none / list)

## New

- (list)

## Changed

- (list)

## Fixed

- (list)

## Upgrade notes

Anything a user must do to pick this up cleanly.
