# workflow-documents

Document artifact providers and a bundled set of document templates for the
[`workflow`](../workflow) plugin.

## Providers

| Name              | URI shape                                 | Notes                                  |
|-------------------|-------------------------------------------|----------------------------------------|
| `document`        | `document:<backend>/<id>`                 | Thin delegator; routes to `<backend>`  |
| `confluence-page` | `confluence-page:<space>/<id>`            | Confluence Cloud REST v2               |

`document` defaults to `file-local` when `<backend>` is omitted. `confluence-page` needs
`CONFLUENCE_BASE_URL`, `CONFLUENCE_USER`, and `CONFLUENCE_TOKEN` in the environment.

## Templates (one skill, eight assets)

Follows the Claude Code skill+template convention. One skill, `document-templates`, bundles eight
fill-in markdown shells as assets. The worker picks the matching shell by name when a workflow step
declares `template: <name>` or when the user asks for one of these kinds.

| Template name          | Purpose                                 |
|------------------------|------------------------------------------|
| `design-document`      | Subsystem / feature design               |
| `implementation-plan`  | Task breakdown for a planned change      |
| `review-note`          | Review findings + verdict                |
| `release-note`         | User-facing release summary              |
| `test-plan`            | Strategy + cases + oracles               |
| `requirement`          | Goal + acceptance criteria               |
| `user-story`           | As-a / I-want-to / So-that               |
| `triage-note`          | Observed / hypothesis / next-check       |

Shells live at `skills/document-templates/templates/<name>.md`; parameter manifests at
`skills/document-templates/manifests/<name>.json`.

Customize: copy a shell to workspace scope (`$REPO/.claude/document-templates/templates/<name>.md`)
or user scope to shadow the plugin's version. The plugin's own shell is never edited in place.

## Install

```bash
claude plugin install workflow-documents@cjhowe-us-workflow
```

Requires `workflow >= 1.0.0`.

## License

Apache-2.0.
