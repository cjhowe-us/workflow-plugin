# gh-branch provider

Creates / reads / deletes branches via the GitHub refs API. Branches on their own don't carry
progress; progress for the work on a branch lives on the PR artifact opened against it.
