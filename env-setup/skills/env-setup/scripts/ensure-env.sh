#!/usr/bin/env bash
# Ensure a user-scope env var is persisted in the user's shell config.
# Idempotent: appends only when the variable is not already set in the
# target file. Shell detection is delegated to detect-shell.sh so every
# supported shell (zsh, bash, fish, sh/ksh, POSIX) uses the right file and
# the right syntax.
#
# Usage:
#   ensure-env.sh --var <NAME> --value <VALUE> [--comment <TEXT>] [--dry-run]
#
# For native Windows PowerShell, use ensure-env.ps1 instead.
set -euo pipefail

VAR=""; VALUE=""; COMMENT=""; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var)     VAR="$2";     shift 2;;
    --value)   VALUE="$2";   shift 2;;
    --comment) COMMENT="$2"; shift 2;;
    --dry-run) DRY_RUN=1;    shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "$VAR"   ]] || { echo "--var required"   >&2; exit 2; }
[[ -n "$VALUE" ]] || { echo "--value required" >&2; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
det=$("$here/detect-shell.sh" --var "$VAR" --value "$VALUE")

# Tiny JSON field extractor (values are single-line simple strings in our schema).
json_get() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\\([^\"]*\\)\".*/\\1/p"; }

shell=$(json_get "$det" shell)
cfg=$(json_get   "$det" config_file)
line=$(json_get  "$det" line)

if [[ -f "$cfg" ]] && grep -q -- "$VAR" "$cfg"; then
  echo "already set in $cfg (shell: $shell). No change."
  exit 0
fi

if (( DRY_RUN )); then
  echo "would append to $cfg (shell: $shell):"
  echo "    $line"
  exit 0
fi

mkdir -p "$(dirname "$cfg")"
touch "$cfg"

if [[ -n "$COMMENT" ]]; then
  printf '\n# %s\n%s\n' "$COMMENT" "$line" >> "$cfg"
else
  printf '\n%s\n' "$line" >> "$cfg"
fi

echo "appended $VAR=$VALUE to $cfg (shell: $shell)."
echo "Open a new shell session (or run 'source $cfg') to pick it up."
