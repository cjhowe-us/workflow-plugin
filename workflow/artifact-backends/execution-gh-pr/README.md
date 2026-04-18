# execution-gh-pr — artifact backend

Backs the `execution` scheme against GitHub PRs.

Mapping:

| Execution field | Backed by |
|-----------------|-----------|
| `uri`           | `execution|execution-gh-pr/<owner>/<repo>/<pr-number>` |
| `status`        | PR state (open → running, merged → complete, closed-without-merge → aborted) |
| `owner`         | PR assignee |
| `body`          | PR body (`<!-- wf:summary -->` + `<!-- wf:ledger -->` sections) |
| `progress`      | PR comments tagged `<!-- wf:progress -->` |
| `lock`          | PR assignee (single-assignee enforcement via GitHub) |

Writes preserve prose outside the `wf:*` markers.
