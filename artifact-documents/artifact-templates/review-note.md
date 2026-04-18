---
name: review-note
scheme: document
description: Fill-in markdown template for review note.
contract_version: 1
inputs:
  - { name: 'subject', type: 'string', required: true }
  - { name: 'subject_ref', type: 'artifact_uri', required: true }
  - { name: 'reviewer', type: 'string', required: true }
output_path: docs/reviews/{{ slug(subject) }}-review.md
---

---
kind: review-note
subject_ref: "{{ subject_ref }}"
reviewer: "{{ reviewer }}"
verdict: pending
---

# Review: {{ subject }}

## Findings

### Blocking

- (none / list)

### Non-blocking

- (list)

## Verdict

- [ ] approve
- [ ] request-changes
- [ ] needs-discussion

## Notes

Free-form reviewer commentary.
