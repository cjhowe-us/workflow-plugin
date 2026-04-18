---
name: author
description: |-
  Meta-workflow — create a new workflow or artifact template. Interactive draft → review → write loop, backed by the `authoring` skill and the `file-local` artifact provider. Writes only to override/workspace/user scope; plugin scope is blocked by the `pretooluse-no-self-edit.sh` hook. Use when the user says "create a workflow", "new template", "scaffold a workflow called X".
---

# author

Three-step template→fill→review cycle that produces a new workflow file or an artifact template
file. Delegates file resolution and validation to the `authoring` skill; uses the `file-local`
artifact provider for writes.

## Step details

### draft

- Prompt the user for: `name`, `description`, SDLC phase tags, inputs, outputs, step graph.
- Generate a candidate markdown+frontmatter file against the `workflow-contract` (or the
  artifact-template shape when `kind` is `artifact-template`).
- Save the draft as a local file under the session's scratch area; the next step reads it from
  there.

### review

- Render the draft.
- Run `tests/workflow-conformance.sh <draft-path>`. If it fails, surface errors inline and loop back
  to `draft` automatically (no user gate needed for validation failures).
- On validation pass, fire the review gate. The user either approves (transition `t2`) or requests
  changes (transition `t3` back to draft).
- An LLM judge at this step proposes the transition based on the validation result + review
  response; confidence below the threshold falls back to the user gate.

### write

- Resolve target path: `authoring.resolve_path(kind, name, scope)`.
- Refuse if path is under a plugin root (double-enforced by hook).
- Write via `file-local.create`.
- Run conformance one more time on the committed path.
- Return `file-local:<relative-path>` as the workflow's output.
