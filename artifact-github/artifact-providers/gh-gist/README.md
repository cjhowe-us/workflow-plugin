# gh-gist provider

Wraps `gh gist` for per-user structured storage. Gists are global (not scoped to a repo) so URIs
carry just the gist id. A gist has one owner (the authenticated user who created it); other users
can only read.

Used by core for the presence gist (`workflow-user-lock-<user>`) and optionally by the `execution`
provider as overflow when the PR body exceeds GitHub's body-size budget.
