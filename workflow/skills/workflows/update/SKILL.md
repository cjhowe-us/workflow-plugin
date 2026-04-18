---
name: update
description: |-
  Meta-workflow — apply edits to an existing workflow or artifact template. Resolves the target via scope precedence (refusing plugin-scope paths), applies the user's edit instructions, validates with workflow-conformance.sh, and writes via file-local. Use when the user says "update the bug-fix workflow", "edit my template", "change X in Y".
---

# update

Edit an existing workflow or artifact template in place. Enforces the plugin-files-immutable rule at
the load step — a URI that resolves to a plugin root is rejected with a clear error pointing the
user at override scope or an external PR.

## Step details

### load

- Resolve URI via scope precedence (`authoring.resolve_path`).
- If resolved path is under any installed plugin root → refuse with the message: "plugin files are
  immutable; copy to workspace or override scope first, or open a PR to the plugin repo."
- Otherwise, read current content; stash for diff.

### edit

- Apply the user's `instructions` to the current content. For small changes, produce a literal
  rewrite; for large ones, propose a structured edit plan and confirm each piece.
- Run `tests/workflow-conformance.sh` on the candidate. If it fails, surface errors and loop back to
  edit (no user gate for validation failures).

### write

- Show a unified diff of current → candidate.
- Fire the review gate. On approval (`t2` completion), write via `file-local.update`. Re-run
  conformance on the committed file.
- On rejection (dynamic branch `t3`), loop back to edit with the user's change requests.
