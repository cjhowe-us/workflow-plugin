# artifact-contract

Artifact providers are **plain scripts, not skills**. Each ships at
`<plugin>/artifact-providers/<name>/` with three files:

- `manifest.json` — machine-readable metadata: `name`, `description`, `contract_version: 1`,
  optional `min_poll_interval_s`.
- `artifact.sh` — the one executable entry point.
- `README.md` — optional human prose documenting backend specifics.

## Invocation

All provider calls go through the plugin's `run-provider.sh` dispatcher:

```text
run-provider.sh <kind> <impl> <subcommand> [--flag value ...]
```

- `<kind>` — the artifact scheme this provider manages (`execution`, `gh-pr`, `document`, ...).
- `<impl>` — implementation name (optional; resolves via registry when empty).
- `<subcommand>` — one of the fixed set below.

The dispatcher resolves the provider's `artifact.sh`, execs it with `<subcommand>` as the first arg
and the remaining flags as-is.

## Subcommand surface

All subcommands accept flag args. All emit one JSON document on stdout. Any runtime error → non-zero
exit code + `{"error": "..."}` on stdout.

### `get --uri U`

Read the artifact's current state. Output: a provider-defined JSON object including at minimum a
canonical `uri`, `kind`, and `status`.

### `create --data F`

Create a new artifact. `F` is a path to a JSON document describing the new artifact (or `-` for
stdin). Output: `{"uri": "...", ...}` including the canonical URI the provider assigned.

### `update --uri U --patch F`

Update fields on an existing artifact. `F` is a JSON patch document (merge semantics,
provider-specific which fields are mutable). Output: `{"uri": U, ...updated-fields}`.

### `list --filter F`

Query artifacts of this scheme. `F` is a provider-specific filter string or a path to a filter JSON
doc. Output: `{"entries": [{...}, ...]}`.

### `lock --uri U --owner O`

Acquire the artifact's lock on behalf of owner `O` (typically a session id or GH user). Provider
decides semantics — e.g. `gh-pr` uses PR assignee, `file-local` uses `flock(2)`. Output:
`{"held": true|false, "owner": "..."}`.

### `lock --uri U --check --owner O`

Non-destructive check: is the lock currently held by `O`? Output:
`{"held": true|false, "current_owner": "..."}`.

### `release --uri U --owner O`

Release the lock. Idempotent. Output: `{"released": true|false}`.

### `status --uri U`

Return the canonical lifecycle status. One of:
`running | blocked | needs_attention | complete | aborted | unknown`. Output:
`{"status": "...", "at": "<ISO8601>", ...}`.

Providers that back **executions** use `status` for completion polling by parents. Providers for
other artifact schemes may map their backend state onto this enumeration (e.g. `gh-pr`: `open` →
`running`, `merged` → `complete`, `closed without merge` → `aborted`).

### `progress --uri U`

Read the artifact's progress log. Output: `{"entries": [...]}` where each entry is
`{at, kind, summary, ...}`. Append-only; reads never mutate.

### `progress --uri U --append F`

Append a progress entry. `F` is a JSON doc (or `-` for stdin). Output: `{"appended": true}`.

## Invariants providers must uphold

1. **Stable URIs.** Once a URI is assigned by `create`, it stays valid for the lifetime of the
   artifact (or until `release`/removal by the backend).
2. **Idempotent writes.** `update` and `release` must be safe to retry.
3. **No silent mutation.** Any change made by `update` is visible on the next `get` without caching.
4. **External mutation reconciliation.** If the backend changes outside the plugin (e.g. someone
   edits a PR on github.com), the next `get` returns the new truth. Providers never cache stale
   state.
5. **Lock honesty.** `lock --check` reflects the real backend state, not a local cache. Mismatch
   must be detectable across sessions and machines.

## Authoring a new provider

1. Pick a unique kind name (`jira-issue`, `slack-thread`, `s3-object`, ...).
2. Scaffold at `<plugin-root>/artifact-providers/<name>/`:
   - `manifest.json` with the keys above.
   - `artifact.sh` (executable) implementing the subcommand surface.
   - `README.md` documenting backend specifics (optional but recommended).
3. Run the conformance test: `tests/provider-conformance.sh artifact-providers/<name>`
4. Ship the plugin; it is auto-discovered at session start.

## Versioning

Breaking changes to the subcommand surface bump the major `contract_version`. Discovery refuses
providers whose major doesn't match core. New optional subcommands ship as minor bumps and are
discovered via the provider's frontmatter `supports:` list (when present).
