# cjhowe-us/workflow — Claude Code Marketplace

Claude Code plugin marketplace containing three plugins that power the development workflow for the
Harmonius game engine.

## Plugins

| Plugin | Purpose |
|--------|---------|
| [`rumdl`](./rumdl) | Markdown LSP + PostToolUse formatter hook + `markdown` coding-standard skill |
| [`coordinator`](./coordinator) | Interactive multi-machine PR dispatch orchestrator. State lives in the PR body itself (single HTML-comment marker). Dispatches up to 3 background worker teammates per orchestrator via agent teams. |
| [`env-setup`](./env-setup) | Cross-platform user-env-var onboarding helper (zsh / bash / fish / sh / ksh / PowerShell). Used as a dependency by other plugins that need to set env vars during onboarding. |

`coordinator` depends on `env-setup` to persist `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
cross-platform. Install both.

## Install

```bash
# Add the marketplace (once)
claude plugin marketplace add cjhowe-us/workflow

# Install env-setup first (coordinator depends on it)
claude plugin install env-setup@cjhowe-us-workflow
claude plugin install coordinator@cjhowe-us-workflow

# Optional: rumdl for Markdown linting/formatting
claude plugin install rumdl@cjhowe-us-workflow
```

## Update

```bash
claude plugin update env-setup@cjhowe-us-workflow
claude plugin update coordinator@cjhowe-us-workflow
claude plugin update rumdl@cjhowe-us-workflow
```

## Uninstall

```bash
claude plugin uninstall coordinator
claude plugin uninstall env-setup
claude plugin uninstall rumdl
```

## Prerequisites

- `coordinator` requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — persist it via the `env-setup`
  skill (`/env-setup:env-setup CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1`) or run
  `env-setup/skills/env-setup/scripts/ensure-env.sh` directly. See
  [`coordinator/README.md`](./coordinator/README.md) for the full requirements.
- `coordinator` also requires the `gh` CLI authenticated with the `repo` scope.
- `rumdl` plugin requires the `rumdl` binary on `PATH`. See [`rumdl/README.md`](./rumdl/README.md)
  for install instructions and `.rumdl.toml` configuration.

## License

Apache-2.0
