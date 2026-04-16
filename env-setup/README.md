# env-setup

Dependency plugin used by other Claude Code plugins to persist user environment variables during
onboarding, in a way that works across shells and platforms.

## Why

When a plugin needs a user-scope env var (for example, `coordinator` requires
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), the "right" place to persist it depends on the user's
shell and OS:

| Shell                      | Target                                  | Syntax                                         |
|----------------------------|-----------------------------------------|------------------------------------------------|
| zsh                        | `~/.zshrc`                              | `export NAME=VALUE`                            |
| bash                       | `~/.bash_profile` or `~/.bashrc`        | `export NAME=VALUE`                            |
| fish                       | `~/.config/fish/config.fish`            | `set -gx NAME VALUE`                           |
| sh / ksh                   | `~/.profile`                            | `export NAME=VALUE`                            |
| PowerShell on Windows      | `HKCU:\Environment` (user registry)     | `[Environment]::SetEnvironmentVariable(...)`   |
| PowerShell on macOS/Linux  | `$PROFILE`                              | `$env:NAME = 'VALUE'`                          |

This plugin centralizes that logic so every consumer plugin gets the same, tested behavior.

## What it provides

- **Skill** `env-setup` — user-invokable (`/env-setup:env-setup`) and auto-triggered when Claude is
  asked to persist an env var. Drives the scripts below.
- **Scripts** under `skills/env-setup/scripts/`:
  - `detect-shell.sh` / `detect-shell.ps1` — emit JSON describing the detected shell, its config
    file, the syntax, and the exact line that would be appended.
  - `ensure-env.sh` / `ensure-env.ps1` — idempotently persist an env var using the detected target.
    Pass `--dry-run` (bash) or `-DryRun` (pwsh) to preview without writing.

## Usage from consumer plugins

```bash
# bash / zsh / fish / sh / ksh
<plugin-root>/../env-setup/skills/env-setup/scripts/ensure-env.sh \
  --var CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS --value 1

# PowerShell (Windows / macOS / Linux)
pwsh -NoProfile -File <plugin-root>/../env-setup/skills/env-setup/scripts/ensure-env.ps1 \
  -VarName CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -VarValue 1
```

Both exit 0 on success. Re-running is a no-op. Add `--dry-run` / `-DryRun` to see the detected
target without writing.

## Windows persistence rationale

`ensure-env.ps1` on Windows writes via `[Environment]::SetEnvironmentVariable(name, value, 'User')`,
which updates `HKCU:\Environment` and broadcasts `WM_SETTINGCHANGE`. Every new process (PowerShell,
cmd, Git Bash, GUI apps) inherits the variable without the user having to edit `$PROFILE`, which
would only affect PowerShell sessions.

## Testing

```bash
pwsh -NoProfile -File env-setup/tests/test-parity.ps1
```

Enforces `.sh` / `.ps1` parity for every script under the plugin.
