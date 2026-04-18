# artifact-template — artifact scheme

A template for producing another artifact. Templates are themselves artifacts; authoring a template means creating one via `/artifact create artifact-template …`, and instantiating from a template means creating an artifact of the template's target `scheme` with the template's payload as input.

## File shape

A template is a single file with YAML frontmatter + body:

```yaml
---
name: design-document
scheme: document
description: Fill-in markdown design doc.
contract_version: 1
inputs:
  - name: title      required: true
  - name: author     required: true
output_path: docs/design/{{ slug(title) }}.md
---

## {{ title }}

Author: {{ author }}

### Context
...
```

Optional frontmatter fields:

- `composes: [...]` — child templates to instantiate alongside. Each becomes a `composed_of` child artifact on the
  parent.
- `references: [...]` — existing artifact URIs the produced artifact depends on. Each becomes a typed edge.

## URIs

`artifact-template|<backend>/<name>` — e.g. `artifact-template|local-filesystem/design-document`.

## Backends

Any backend that can store text files can back the `artifact-template` kind. `local-filesystem` (this plugin) stores templates at `<worktree>/artifact-templates/<name>.md`. Plugin-shipped templates live in the plugin's `artifact-templates/` directory and are discoverable by name.
