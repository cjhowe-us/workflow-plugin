# execution — artifact scheme

Canonical record of a workflow run. Workflow-domain status vocabulary:
`running`, `needs_attention`, `aborted`, `complete`.

URIs: `execution|<backend>/<backend-specific-id>` —
e.g. `execution|execution-gh-pr/<owner>/<repo>/<pr-number>`.

Default backend: `execution-gh-pr` (maps an execution 1:1 with a GitHub PR — summary + step ledger in
the PR body, progress log in PR comments).

See `schema.json` for the declarative field + subcommand contract.
