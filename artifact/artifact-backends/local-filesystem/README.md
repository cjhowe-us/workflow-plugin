# local-filesystem — artifact backend

Stores artifacts on the local filesystem.

- Backs the `file` scheme: URIs are `file|local-filesystem/<relative-path>`, resolved against the current git worktree
  root.
- Supports create / get / update / list / lock / release / status / progress.
- No edge persistence in contract_version 1 (composition is recorded via companion `.edges.json` siblings once the graph
  contract is extended).

Locks are a sibling `<path>.lock` file containing the owner. Progress entries append to a sibling
`<path>.progress.jsonl`.
