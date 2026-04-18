# gh-milestone provider

Read/write GitHub milestones via `gh api /repos/<r>/milestones`. Milestones don't have assignees;
lock subcommands succeed as no-ops. Progress events are milestone description updates.
