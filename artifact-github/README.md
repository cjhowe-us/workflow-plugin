# workflow-github

GitHub artifact providers for the [`workflow`](../workflow) plugin. Required for teams using GitHub
as the primary backend.

## Providers

| Name          | URI shape                              | Kind                        |
|---------------|----------------------------------------|------------------------------|
| `gh-pr`       | `gh-pr:<owner>/<repo>/<n>`             | PR (assignee = owner lock)   |
| `gh-issue`    | `gh-issue:<owner>/<repo>/<n>`          | Issue (assignee = owner lock)|
| `gh-release`  | `gh-release:<owner>/<repo>/<tag>`      | Release (no lock)            |
| `gh-milestone`| `gh-milestone:<owner>/<repo>/<n>`      | Milestone (no lock)          |
| `gh-tag`      | `gh-tag:<owner>/<repo>/<tag>`          | Git tag (no lock)            |
| `gh-branch`   | `gh-branch:<owner>/<repo>/<branch>`    | Git branch (no lock)         |
| `gh-gist`     | `gh-gist:<gist-id>`                    | Gist (creator = owner)       |

Each provider ships `artifact.sh` implementing the
[artifact-contract](../workflow/skills/contracts/artifact-contract/SKILL.md) subcommand surface.

## Install

```bash
claude plugin install workflow-github@cjhowe-us-workflow
```

Requires `workflow >= 1.0.0` and the `gh` CLI (`gh auth login`).

## Defaults

When the core plugin's `execution` provider looks up an implementation for `execution:`-kind URIs,
it resolves to `gh-pr` (since PRs are the natural backing). Other kinds resolve by name match.

## License

Apache-2.0.
