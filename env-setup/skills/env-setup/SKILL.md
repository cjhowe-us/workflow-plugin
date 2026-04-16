---
name: env-setup
description: >
  Persist an environment variable for the user across shells and platforms.
  Detects zsh / bash / fish / sh / ksh / PowerShell and writes to the
  correct config (rc file, `$PROFILE`, or `HKCU:\Environment` registry on
  Windows PowerShell). Used during plugin onboarding when a user-scope env
  var must outlive the current shell. Idempotent; supports a dry-run
  preview that shows the detected target and the exact line that would be
  written before committing anything. Trigger when the user asks to
  "persist an env var", "add to my shell profile", "set a user env var",
  "onboard the plugin's env var", or a plugin's SessionStart hook tells
  them an env var must be set.
argument-hint: <VAR_NAME> <VALUE> [--dry-run]
allowed-tools: Bash, Read, AskUserQuestion
---

# env-setup — persist an env var across shells and platforms

Use this skill whenever a user needs to make an environment variable permanent on their machine. The
skill owns the shell detection and the correct write target for every supported platform.

## Supported matrix

| Shell                      | Target                                  | Syntax                                         |
|----------------------------|-----------------------------------------|------------------------------------------------|
| zsh                        | `~/.zshrc`                              | `export NAME=VALUE`                            |
| bash                       | `~/.bash_profile` or `~/.bashrc`        | `export NAME=VALUE`                            |
| fish                       | `~/.config/fish/config.fish`            | `set -gx NAME VALUE`                           |
| sh / ksh                   | `~/.profile`                            | `export NAME=VALUE`                            |
| PowerShell on Windows      | `HKCU:\Environment` (user registry)     | `[Environment]::SetEnvironmentVariable(...)`   |
| PowerShell on macOS/Linux  | `$PROFILE`                              | `$env:NAME = 'VALUE'`                          |

## Playbook

1. **Parse the request.** Extract the variable name and the value. If either is ambiguous, surface
   `AskUserQuestion` to confirm. Do not write without a concrete name + value.

2. **Pick the script.** If the user is on Windows (detected via `[[ "$OSTYPE" == msys* ]]`,
   `$IsWindows` in pwsh, or asking explicitly), prefer the PowerShell path. Otherwise prefer bash.

3. **Dry-run first.** Run the chosen script with `--dry-run` (bash) or `-DryRun` (pwsh). It prints
   the detected target file / registry key and the exact line that would be written.

4. **Confirm with the user** via `AskUserQuestion` before writing. Show them the detected target +
   line from step 3.

5. **Commit.** Re-run without the dry-run flag. The script is idempotent — if the variable is
   already set to the requested value, it's a no-op.

6. **Tell the user to open a new shell** to pick up the variable. The current process's environment
   is unchanged until the shell reloads.

## Scripts

Paths are relative to this skill's root:

- `scripts/detect-shell.sh` / `scripts/detect-shell.ps1` — emit JSON describing the detected shell,
  the target file or registry key, the syntax, and the exact line the env var would be written as.
- `scripts/ensure-env.sh` / `scripts/ensure-env.ps1` — drive `detect-shell` internally and persist
  the env var.

### Examples

```bash
# Bash path.
./scripts/ensure-env.sh --var CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS --value 1

# Dry-run preview.
./scripts/ensure-env.sh --var MY_VAR --value abc --dry-run

# PowerShell path (works on all three OSes, but on macOS/Linux is only
# useful for PowerShell-specific env vars).
pwsh -NoProfile -File ./scripts/ensure-env.ps1 -VarName MY_VAR -VarValue abc -DryRun
```

## Never

- Write a variable without the user's explicit consent (dry-run + `AskUserQuestion` first).
- Overwrite a file outside the known targets above.
- Expand the list of supported shells silently — every new shell needs a documented case in
  `detect-shell.{sh,ps1}` and a corresponding test in this plugin's test suite.
- Assume the caller's current process will see the new variable; always advise a shell restart.
