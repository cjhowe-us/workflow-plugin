---
name: artifact
description: This skill should be used when the user types `/artifact` or asks to "show a PR", "show an issue", "inspect an artifact", "list my PRs", "list documents", "what's the status of X", "progress on <uri>", "check the lock on this PR", "add a provider for jira", "add a provider plugin", or mentions artifact providers (gh-pr, gh-issue, document, confluence-page, execution, file-local, etc.). Handles inspect / list / query on any artifact, and scaffolds new provider plugins.
---

# artifact

The `/artifact` entry point for reading and inspecting artifacts via their providers. Any artifact
(PR, issue, release, doc, execution, gist, Figma, Jira ticket, …) routes through the same provider
contract, so the sub-commands here work uniformly across kinds.

## Sub-command shape

| Pattern                                  | What to do                                    |
|------------------------------------------|------------------------------------------------|
| "show <uri>"                              | `run-provider.sh <kind> "" get --uri <uri>`   |
| "list <kind> [--filter ...]"              | `run-provider.sh <kind> "" list --filter ...`|
| "status <uri>"                            | `run-provider.sh <kind> "" status --uri ...` |
| "progress <uri>"                          | `run-provider.sh <kind> "" progress --uri ...`|
| "lock <uri> --owner <user>"               | `run-provider.sh <kind> "" lock --check ...` |
| "add a provider [for <backend>]"          | Run the `extension-scaffold` flow             |
| "list providers"                          | Read registry; filter by kind                 |
| "show discovery"                          | Print `$XDG_STATE_HOME/workflow/registry.json` |

## Provider dispatch

All artifact operations go through `run-provider.sh` in the core plugin. The script resolves the
provider by artifact scheme (first segment of the URI before `:`) against the registry, then execs
that provider's `artifact.sh` with the sub-command + args.

Writes (`create`, `update`) are rare from `/artifact` directly — they usually come from a running
workflow's step, not an ad-hoc user command. When a user does ask to mutate an artifact directly,
confirm via `AskUserQuestion` before calling through.

## Scaffolding a new provider plugin

When the user wants a provider for a new backend (e.g. Jira, Linear, a custom REST system), route to
the `extension-scaffold` flow. The scaffold generates a sibling Claude Code plugin shell with the
right directory layout (`artifact-providers/<name>/{manifest.json, artifact.sh}`) — the user fills
in the backend-specific script afterward using `references/artifact-contract.md` as the guide.

## References

Load only when the user's intent requires:

- `references/artifact-contract.md` — the provider protocol surface (subcommands, flags, JSON
  shapes, error paths). Load when authoring or debugging a provider.
- `references/discovery.md` — registry shape, scope precedence, how providers are discovered, how to
  debug a missing one.
- `references/extension-scaffold.md` — scaffolding a new provider plugin.

## Related skills

- `/workflow` — run workflows (which produce artifacts).
- `/template` — author workflows and artifact templates.
