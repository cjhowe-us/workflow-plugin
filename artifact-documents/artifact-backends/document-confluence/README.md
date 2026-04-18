# confluence-page provider

Wraps Atlassian Confluence Cloud's REST API. Requires:

- `CONFLUENCE_BASE_URL` (e.g. `https://acme.atlassian.net/wiki`).
- `CONFLUENCE_TOKEN` — an API token with page-read/write scope.
- `CONFLUENCE_USER` — Atlassian email for basic auth.

Scope: Confluence Cloud only; Data Center instances need a separate provider because their API
differs. Progress events live as page edits; each edit carries a `<!-- wf:progress {...} -->` HTML
comment the provider scrapes on read.

## Known limitations

- Atomic updates use page version numbers. Concurrent writers race; the provider retries once on
  version-conflict, then returns `{"error":"lock-mismatch"}`.
- "Assignee" isn't a native Confluence concept — the provider treats the page's `owner` (per REST)
  as the lock. Some Confluence instances restrict who can change the owner; the provider surfaces
  the error when that happens.
