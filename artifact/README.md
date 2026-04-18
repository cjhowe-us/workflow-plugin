# artifact

The artifact plugin. Owns three things:

1. **Artifact** — any file, record, or external-system object the system touches.
2. **Artifact template** — a directory bundle that produces an artifact when instantiated.
3. **Artifact provider** — a script bundle that implements CRUD on one artifact scheme.

Everything else in the plugin (the `/artifact` entry skill, the registry, dispatch scripts, JSON schemas, conformance
tests) is machinery in service of those three concepts.

Zero plugin dependencies. Needs `gh`, `git`, `jq`, `bash` on PATH.

## Install

```bash
claude plugin marketplace add cjhowe-us/workflow
claude plugin install artifact@cjhowe-us-workflow
```

Other plugins in the ecosystem (workflow, artifact-github, artifact-documents, workflow-sdlc) all depend on this.

## Architecture

Two primitives split across two reference plugins:

| Plugin      | Concern                                                |
|-------------|--------------------------------------------------------|
| `artifact`  | Artifacts + templates + providers (this plugin)         |
| `workflow`  | Workflows + workers + orchestration (separate plugin)   |

Domain extensions (`artifact-github`, `artifact-documents`) ship additional providers. `workflow-sdlc` ships composable
templates and canned workflows.

## Artifact template shape

Each template is a directory:

```text
artifact-templates/<name>/
  manifest.json        # required
  instantiate.sh       # required, executable — produces the artifact
  README.md            # optional
  schema.json          # optional — JSON schema for validated inputs
  template.md          # optional — markdown shell with {{ placeholder }} fields
  request.json.tmpl    # optional — any companion assets the entry_script reads
  examples/            # optional — sample outputs
```

Instantiation flow:

1. `/artifact create <template>` resolves the template via the registry.
2. `instantiate-template.sh` validates incoming inputs against the manifest.
3. Execs `<template-dir>/<entry_script>` with inputs as JSON on stdin and the template directory path as argv[1].
4. The script emits `{"uri": "..."}` on stdout for the newly-created artifact.

Deterministic bash throughout — no LLM in the instantiation path. Authors ship any shape they want inside
`instantiate.sh` and its companion assets.

## Provider contract

See [`contracts/artifact-provider.schema.json`](contracts/artifact-provider.schema.json) and the core
`artifact-contract` reference under `skills/artifact/references/`.

Each provider ships `<plugin>/artifact-providers/<name>/` with:

- `manifest.json` — name, description, contract_version, optional min_poll_interval_s.
- `artifact.sh` — executable implementing get / create / update / list / lock / release / status / progress subcommands.
- `README.md` — backend-specific notes (recommended).

## License

Apache-2.0.
