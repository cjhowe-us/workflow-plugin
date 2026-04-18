---
name: triage-note
scheme: document
description: Fill-in markdown template for triage note.
contract_version: 1
inputs:
  - { name: 'title', type: 'string', required: true }
  - { name: 'incident_ref', type: 'artifact_uri', required: false }
  - { name: 'triaged_by', type: 'string', required: true }
  - { name: 'severity', type: 'string', required: false, default: 'sev-3' }
output_path: docs/triage/{{ slug(title) }}.md
---

---
kind: triage-note
incident_ref: "{{ incident_ref }}"
triaged_by: "{{ triaged_by }}"
severity: "{{ severity }}"
---

# Triage: {{ title }}

## Observed behavior

What the user / monitoring sees. Paste logs, screenshots, or links.

## Hypothesis

Most likely cause, with reasoning.

## Next check

Concrete next action to confirm or reject the hypothesis.

## Fallback

If the hypothesis is wrong, where to look next.

## Severity

- [ ] sev-1 — user-facing outage
- [ ] sev-2 — significant degradation
- [ ] sev-3 — minor / workaround exists
