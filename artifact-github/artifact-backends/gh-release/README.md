# gh-release provider

Wraps `gh release` for publishing and inspecting releases. Releases are one-shot so there's no
assignee-lock concept; the `lock` subcommands always succeed as no-ops. Progress-on-release isn't
meaningful — `progress --append` writes to the release body's `<!-- wf:notes -->` section instead.
