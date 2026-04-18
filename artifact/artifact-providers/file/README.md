# file — artifact scheme

A leaf artifact representing a file (text or binary bytes) at a path.

URIs: `file|<backend>/<backend-specific-path>`.

Default backend: `local-filesystem` (writes to the current git worktree). Any backend that declares `backs_schemes: [file]` can serve this scheme — S3, cloud storage, a git-tree-object store, etc.

See `schema.json` for the full field + subcommand contract.
