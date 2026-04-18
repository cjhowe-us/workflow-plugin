---
name: conductor
description: |-
  The single meta-workflow — a workflow that creates, edits, reviews, and deletes other workflows and artifact templates. Four modes dispatched via the `mode` input: `create` scaffolds a new artifact; `update` edits in place; `review` audits (read-only); `delete` removes. Delegates CRUD to the artifact plugin's subcommand surface (`create` / `get` / `update` / `delete`); conductor adds the interactive LLM draft + gate + conformance-check loop on top. Triggered by "create a workflow", "new template", "update the bug-fix workflow", "review the cut-release workflow", "delete my-template".
---

# conductor

Conductor is the only meta-workflow: a workflow that operates on other workflows (and artifact
templates). One flow covers the full CRUD surface via conditional steps on the `mode` input:

| Mode     | load | draft | critique | confirm gate | commit                               |
|----------|------|-------|----------|--------------|--------------------------------------|
| create   | —    | ✔     | —        | approve draft | `artifact.create` at resolved path  |
| update   | ✔    | ✔     | —        | approve diff  | `artifact.update` on the original URI |
| review   | ✔    | —     | ✔        | approve report | `artifact.create` review-note doc   |
| delete   | ✔    | —     | —        | confirm destruction | `artifact.delete`                |

No separate `update`, `review`, or `delete` workflows — conductor is the single entry point for
authoring changes to anything. The CRUD primitives are artifact-plugin subcommands; conductor
wraps them with interactive drafting, LLM critique, and confirmation gates.

## Expanding the artifacts plugin

Conductor drives its steps entirely through the artifact subcommand surface:

- `artifact get --uri <uri>` — read target for update / review / delete
- `artifact create --scheme <s> --data <json>` — scaffold new artifact
- `artifact update --uri <uri> --patch <json>` — in-place edit
- `artifact delete --uri <uri>` — remove
- `artifact create --scheme document --data <review-note>` — review mode writes a
  review-note document referencing the target

If a new CRUD-ish operation needs first-class support (e.g. `artifact move`, `artifact rename`,
`artifact fork`), it lands in the artifact plugin's kind schema first; conductor picks it up
by adding a matching `mode` + step.

## Conditional steps

Each step is gated by `when: "<expression>"` on the mode input. See
`../../skills/workflow/references/workflow-contract.md` for the full rule. The engine skips a
step whose `when` is falsy; its outbound transitions flow from the preceding step's `to` as if
the step were inlined away.
