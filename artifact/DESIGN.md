# artifact plugin — design document

Source of truth for the artifact primitive's architecture. Append-only changelog at the bottom records material design
decisions. Edits that change these choices must add a dated entry here.

## Problem

Workflow- and knowledge-oriented plugins need a single, uniform primitive for every read or write: local files, markdown
docs, GitHub PRs and issues, Jira tickets, Confluence pages, persisted AI conversations, workflow executions, template
definitions. Each external system is wildly different, but plugin authors should not care. They should declare "this
operation produces an artifact of type X" and the engine should route it to the right storage.

Authoring a new provider has been too heavy — every new system (Jira, Slack, …) had to invent a new *scheme* even when
the semantic scheme already existed. And template authoring required a full directory of files per template. Both
friction points are resolved here.

## Non-goals

- A workflow engine. That lives in the separate `workflow` plugin, which depends on this one.
- A caching layer, CRDT, or file server. The artifact plugin *points to* external state; it does not duplicate it.

## Goals

- **Three concepts, nothing else.** Provider, backend, artifact. Templates are themselves artifacts; directories are
  themselves artifacts. Generality comes from consistent application of the same primitives, not from inventing new
  ones.
- **Declarative over imperative.** Providers ship a JSON schema; backends conform. Templates carry frontmatter + body;
  the engine routes. Bash scripts glue together the 5% that cannot be declared.
- **Generic and flexible.** External consumers plug in as backends — no new schemes required. A Jira backend gains every
  consumer of `issue|...` immediately.
- **Artifacts compose.** Composition is a graph relation; the same machinery tracks directory→child, execution→step,
  release→PR, and template→template-it-built-on.
- **Zero plugin dependencies for artifact itself.** Only `gh`, `git`, `jq`, `bash` on PATH. All other plugins in the
  ecosystem depend on artifact and on nothing of each other they can avoid.

## The three concepts

### 1. Provider = type of artifact

A **provider** defines an artifact type. The `issue` provider *is* the definition of what an `issue` artifact is: its
fields, its URI scheme, the subcommand surface every backend must implement for it, and the graph relations it supports.

Provider directory layout:

```text
artifact-providers/<scheme>/
  manifest.json            # name, description, contract_version
  schema.json              # declarative: fields, subcommands, relations
  artifact.sh              # thin mediator — routes to the selected backend
  README.md                # human documentation
```

The mediator script is ~30 lines. Its job:

1. Parse the URI (if the call is URI-addressed) or look up the user's preferred backend for this scheme.
2. Validate inputs against the scheme's `schema.json`.
3. Exec the selected `artifact-backends/<name>/artifact.sh` with the same argv.
4. Validate the backend's output against the schema before returning.

All backend-specific logic lives under `artifact-backends/<name>/`, never in the provider directory.

### 2. Backend = storage implementation

A **backend** stores an artifact's state in an external system. **The scheme ↔ backend relationship is many-to-many:**
one scheme may have many backends (an `issue` can be backed by GitHub, Jira, or local-filesystem); one backend may back
many schemes (a filesystem backend realizes `file`, `directory`, `artifact-template`, `preferences` all against the same
local tree).

Backend directory layout:

```text
artifact-backends/<backend-name>/
  manifest.json            # name, description, backs_schemes: [...], capability flags
  artifact.sh              # implements the scheme's subcommand surface
  README.md
```

A backend manifest declares:

- `backs_schemes: [issue, pr, …]` — every scheme the backend can realize.
- Capability flags: `supports_locking`, `supports_edges`, `min_poll_interval_s`, …

External consumers (Jira, Slack, custom SaaS) plug in exclusively as backends. They never invent new schemes.

#### Generic file backends

A backend is *generic* when it can back multiple filesystem-friendly schemes — typically `file`, `directory`,
`document`, and `artifact-template`. The `local-filesystem` backend shipped here is one such generic backend: it stores
any filesystem-friendly scheme under the current git worktree (`file|local-filesystem/<rel>`,
`directory|local-filesystem/<rel>`, `document|local-filesystem/<rel>`, …).

Users (and external plugin authors) can ship their own generic file backends by:

1. Creating `artifact-backends/<backend-name>/` in a plugin, workspace, or user scope.
2. Declaring `backs_schemes: [file, directory, document, artifact-template]` (any subset the backend actually handles).
3. Implementing `artifact.sh` so each scheme's subcommand surface maps onto the external system's object model.

Examples a user might ship:

- `s3-filesystem` — stores artifacts as S3 keys.
- `sftp-filesystem` — stores artifacts on a remote SFTP host.
- `git-tree` — stores artifacts as git tree objects in a dedicated branch.

The contract is entirely about conforming to the *scheme's* schema. Nothing in the engine hard-codes
"filesystem-backed"; any backend that implements the file / directory / document / artifact-template schemas is fungible
with `local-filesystem`. Users opt in per scheme via `preferences|user-config/backends` (or per call via `--backend`).

### 3. Artifact = instance managed by provider + backend

An **artifact** is addressed by URI:

```text
<scheme>|<backend>/<path>
```

Examples:

- `issue|gh-issue/myorg/myrepo#42` — a GitHub issue
- `issue|jira-issue/PROJ-123` — a Jira issue
- `document|document-filesystem/~/notes/design.md` — a local markdown doc
- `execution|execution-gh-pr/myorg/myrepo#99` — a workflow execution backed by a GitHub PR

The provider + backend together own the artifact's state. The artifact plugin never caches state beyond a machine-local
graph index (see Local state below).

## Templates are artifacts

An **artifact template** is an artifact of scheme `artifact-template`. Its payload is the instantiation input for
another provider's `create` subcommand.

- Authoring: `/artifact create artifact-template name=<x> scheme=<target-scheme> …`
- Instantiating: `/artifact create <template-uri> title=Foo author=Bar` → the `artifact-template` provider reads the
  template artifact, interpolates the supplied inputs, and dispatches to the target provider's `create`. The target
  provider returns the new artifact's URI.

Template file shape (YAML frontmatter + body, single file on disk):

```yaml
---
name: design-document
scheme: document               # target provider — what this template produces
description: Markdown design doc with standard sections
contract_version: 1
inputs:
  - name: title      required: true
  - name: author     required: true
---

# {{ title }}

Author: {{ author }}

## Context
## Non-goals
## Goals
```

Optional composition fields in frontmatter:

- `composes: [...]` — child templates to instantiate alongside. Each child becomes a child artifact linked by a
  `composed_of` edge. Child inputs are bound from parent inputs via `{{ … }}`.
- `references: [...]` — existing artifact URIs the new artifact depends on. Each becomes a `depends_on` (or
  other-relation) edge.

Optional sibling files in the same directory — e.g. `workflow-execution.request.json` alongside `workflow-execution.md`
— are read by the target provider's `create` as companion assets. No manifest; no `instantiate.sh`. The provider
interprets the template.

## Directories are artifacts

A **directory** is an artifact of scheme `directory`. Backends that support it write a filesystem subtree (or equivalent
hierarchy in the backend's native shape).

Directory templates are multi-file: one template file declares `scheme: directory` and uses `composes:` to name child
templates, each with a `path:` inside the directory. The `directory` provider instantiates each child recursively and
records every child as a `composed_of` edge on the new directory artifact.

Example:

```yaml
---
name: release-bundle
scheme: directory
description: Release packet — design doc + test plan + release note
inputs:
  - name: version     required: true
  - name: owner       required: true
composes:
  - template: design-document
    path: design/design-doc.md
    inputs: { title: "Release {{version}}", author: "{{owner}}" }
  - template: test-plan
    path: tests/test-plan.md
    inputs: { owner: "{{owner}}", scope: "release {{version}}" }
  - template: release-note
    path: release/notes.md
    inputs: { version: "{{version}}" }
contract_version: 1
---
```

## Contracts

### Per-scheme schema (`artifact-providers/<scheme>/schema.json`)

The single source of truth for what an artifact of this scheme looks like and what any backend must implement:

```jsonc
{
  "scheme": "issue",
  "fields": {
    "title":    { "type": "string",    "required": true },
    "body":     { "type": "markdown" },
    "status":   { "type": "enum", "values": ["open", "closed"] },
    "assignee": { "type": "string" }
  },
  "subcommands": {
    "create": { "required": true,  "in": ["title", "body", "assignee"], "out": ["uri"] },
    "get":    { "required": true,  "in": ["uri"], "out": ["title", "body", "status", "assignee", "edges"] },
    "update": { "required": true,  "in": ["uri", "patch"], "out": ["uri"] },
    "list":   { "required": true,  "in": ["filter"], "out": ["uris"] },
    "delete": { "required": false, "in": ["uri"], "out": ["ok"] },
    "lock":   { "required": false, "in": ["uri"], "out": ["token"] },
    "edges":  { "required": false, "relations": ["closes", "depends_on", "bundled_in"] }
  }
}
```

Provider mediator enforcement:

- **At discovery.** Every registered backend is matched against the schema. Missing required subcommands mark the
  backend `incomplete`; it isn't offered as a default, and calls that need those subcommands surface a clear diagnostic.
- **At call time.** Inputs validated against the subcommand's `in` before exec. Backend output parsed + checked against
  `out`. Malformed output fails the call with a `schema-mismatch` error — no silent misinterpretation.
- **For templates.** A template's `inputs` must name fields declared in the target scheme's schema, unless the target
  provider tolerates extra inputs explicitly.

Schemas are declarative JSON; no executable content. They are the stable contract that keeps all backends of a scheme
fungible.

### Artifact graph

Composition and cross-artifact references are edges on a typed graph. Every provider's `get` response includes:

```jsonc
{
  ...,
  "edges": [
    { "target": "issue|gh-issue/myorg/repo#12", "relation": "closes" },
    { "target": "file|local-filesystem/~/a.md", "relation": "composed_of" }
  ]
}
```

Supported relations (schemes may add more in their schema):

- `composed_of` — parent → child (a directory's children, an execution's steps, a release's bundled PRs).
- `depends_on` — gating relation used by workflows.
- `closes` — PR closes issue; any "resolves" semantics.
- `bundled_in` — inverse of `composed_of` where the backend only stores it that way around.
- `mentions`, `cites`, `supersedes` — LLM-knowledge-graph relations.

Optional provider subcommands:

- `edges --uri U [--relation R] [--depth N]` — walk outward. Default depth 1.
- `find --relation R --target U` — reverse lookup. Default returns empty unless the backend indexes.

Backends store edges in backend-natural form: GitHub PR body `Closes #NN` parsed; issue comment
`<!-- artifact:edges -->`; sibling `.edges.json` for filesystem artifacts; linked-pages list on Confluence.

**Composition is the same mechanism everywhere.** Templates composing other templates → `composed_of` on the artifacts
they produce. Directories containing files → `composed_of`. Releases bundling PRs → `composed_of`. No separate
"container" machinery.

### Backend resolution

URI-addressed operations (`get`, `update`, `delete`, operations against a known artifact) dispatch directly to the named
backend in the URI.

Scheme-addressed operations (`create`, `list` without a URI) resolve in this strict order:

1. **Per-call `--backend <name>` override.** Highest priority. Scoped to that one call.
2. **Saved user preference.** `backends.<scheme>.default` read from the preferences store.
3. **Sole-backend short-circuit.** If exactly one backend is installed for the scheme, use it and persist it as the
   user's preference (transparent write).
4. **Prompt.** If multiple backends are installed and no default is set, the `/artifact` skill prompts the user once
   ("Which backend for `document`? `document-filesystem` (local) or `document-confluence` (hosted)?"), then persists the
   answer.

**No alphabetical tiebreak. No silent random selection.** If the engine can't decide, it asks.

## Local state

All provider/backend configuration and computed caches live on the user's machine. A shared helper (`scripts/xdg.sh`)
resolves per-OS paths.

### Preferences (config dir)

Per-scheme backend defaults, tutor-completion flag, user-scoped overrides, WIP caps. Written by the `preferences` scheme
via its `user-config` backend.

- Linux: `${XDG_CONFIG_HOME:-$HOME/.config}/artifact/preferences/`
- macOS: `~/Library/Application Support/artifact/preferences/`
- Windows: `%APPDATA%\artifact\preferences\`

### Graph cache (cache dir)

Edge index, recent `graph expand` results, materialized knowledge-graph views. Written by `scripts/graph.sh` as it walks
edges. Cache entries keyed on the source artifact's `updated_at`, so external mutations to artifacts invalidate the
cache on next `get`.

- Linux: `${XDG_CACHE_HOME:-$HOME/.cache}/artifact/graph/`
- macOS: `~/Library/Caches/artifact/graph/`
- Windows: `%LOCALAPPDATA%\artifact\graph\`

### Discovery registry (cache dir)

`scripts/discover.sh` runs at session start and writes a consolidated JSON registry of schemes, backends, templates, and
workflows across every installed plugin. Rebuilt every session; never authoritative — the plugin files are.

### Ephemeral state (state dir)

Flocks and per-machine runtime state (e.g. the orchestrator lock owned by the `workflow` plugin) go under:

- Linux: `${XDG_STATE_HOME:-$HOME/.local/state}/`
- macOS: `~/Library/Application Support/` (reused; macOS has no distinct state dir)
- Windows: `%LOCALAPPDATA%\`

## Key invariants

1. **Three concepts only.** Provider, backend, artifact. Everything else is implementation detail.
2. **Templates are artifacts.** One discovery path, one conformance test set, one graph for template composition and
   runtime composition.
3. **Directories are artifacts.** Same recursive composition as any other container artifact.
4. **Provider = type; backend = storage.** External consumers plug in as backends, not schemes.
5. **Backends conform to a per-scheme declarative schema.** Enforced at discovery and at call time.
6. **URI format is `<scheme>|<backend>/<path>`.** The backend is always addressable.
7. **Backend resolution never silently picks.** URI > override > preference > sole-backend > prompt.
8. **Composition is a graph relation.** `composed_of` for every container artifact; same machinery for templates,
   directories, executions, releases.
9. **No in-repo runtime state.** All artifact state lives in backends. Machine-local files hold only cache, preferences,
   and ephemeral state.
10. **Plugin files are immutable to agents.** Changes come via override scope (workspace/user) or external PR.
11. **External mutations are first-class.** The next `get` returns updated state; the graph cache invalidates via
    `updated_at`.
12. **JSON everywhere except markdown frontmatter.** Manifests, schemas, provider I/O — JSON. Template + workflow
    descriptors — YAML frontmatter (Claude Code convention) with an otherwise-opaque body.

## Dogfooding

Every dependent plugin is a reference plugin for this one. If any cross-plugin link needs a special case, the contract
is wrong — fix the contract, not the consumer.

- `workflow` depends on `artifact` and consumes its full surface: the worker calls `artifact/scripts/run-provider.sh`
  for every PR, issue, document, execution, and step it touches.
- `artifact-github` and `artifact-documents` each ship schemes plus backends, following the contracts here.
- Future external consumers (Jira, Slack, Notion, …) plug in as backends against existing schemes. They never
  monkey-patch the contracts.

## Design changelog

Append-only.

| Date       | Decision |
|------------|----------|
| 2026-04-18 | Extracted artifact primitive from the `workflow` plugin. Artifact owns provider + backend + artifact concepts, templates (as artifacts of scheme `artifact-template`), directories (as artifacts of scheme `directory`), and the typed-edge graph. Zero plugin dependencies. |
| 2026-04-18 | Provider/backend split. Provider defines an artifact *type* (scheme) via `schema.json`; backends store state in external systems and declare `backs_schemes` conformance. External consumers plug in as backends, not as new schemes. |
| 2026-04-18 | Templates are artifacts of scheme `artifact-template`. Single-file shape with YAML frontmatter (no directory bundles, no `instantiate.sh`). Composition via `composes:` (child templates) and `references:` (existing artifact URIs). |
| 2026-04-18 | Directories are artifacts of scheme `directory`. Directory templates are multi-file via tree specs in `composes`. |
| 2026-04-18 | Typed-edge graph is first-class. `composed_of` is the universal composition relation; other relations (`depends_on`, `closes`, `bundled_in`, `mentions`, `cites`, `supersedes`) are named in each scheme's schema. `scripts/graph.sh` exposes `expand / path / dot` for cross-provider traversal. |
| 2026-04-18 | Backend resolution is URI → override → saved preference → sole-backend short-circuit → prompt. No alphabetical fallback. |
| 2026-04-18 | Local state paths via `scripts/xdg.sh`: preferences in the user's config dir; graph cache + discovery registry in the user's cache dir; ephemeral state (flocks) in the state dir. Windows-compatible. |
| 2026-04-18 | Repository layout: `cjhowe-us/artifact` hosts this plugin plus `artifact-github` and `artifact-documents`. `cjhowe-us/workflow` keeps the workflow plugin. `cjhowe-us/marketplace` hosts only `marketplace.json` pointing at the plugin repos. |
